#!/bin/bash
set -euo pipefail

# ----------------------------- #
#          Configuration        #
# ----------------------------- #

# AWX Installation Variables
AWX_NAMESPACE="awx"
AWX_OPERATOR_VERSION="2.12.0"
ANSIBLE_RUNNER_IMAGE="gaianmobius/awx:v0.3"
AWX_SERVICE_TYPE="NodePort"
AWX_ADMIN_USER="admin"
AWX_ADMIN_PASSWORD=""  # Will be retrieved after AWX installation

# AWX Access Variables
NODE_IP=""               # To be fetched dynamically
NODE_PORT=""             # To be fetched dynamically
AWX_API_TOKEN=""         # Will be generated after AWX installation
AWX_HOST=""              # Will be constructed using NODE_IP and NODE_PORT

# AWX Resource Setup Variables
#ORGANIZATION_NAME="Mobius"
INVENTORY_NAME="AWX Runner"
INVENTORY_DESCRIPTION="AWX Hosts Inventory"
RUNNER_DNS="ansible-runner.${AWX_NAMESPACE}.svc.cluster.local"
GITHUB_CRED_NAME="DurgaPrasad GitHub Token"
GITHUB_USERNAME="godnani2006"  # Set this or pass as a variable
GITHUB_TOKEN="ghp_xxxxx"        # Set this or pass as a variable
ORGANIZATION_ID="1"
GITHUB_REPO_URL="https://github.com/gaiangroup/awx"
PROJECT_NAME="Ansible-Runner"
PROJECT_DESCRIPTION="Running Tasks"


# ----------------------------- #
#          Helper Functions     #
# ----------------------------- #

# Function to check if a command exists
command_exists() {
  command -v "$1" &>/dev/null
}

# Function to install dependencies
install_dependencies() {
  echo "Checking for required commands..."

  for cmd in kubectl helm curl jq; do
    if ! command_exists "$cmd"; then
      echo "Error: $cmd is not installed. Please install it before running this script."
      exit 1
    fi
  done

  echo "All required commands are available."
}

# Function to install AWX Operator and AWX instance
install_awx() {
  echo "Adding AWX Operator Helm repository..."
  helm repo add awx-operator https://ansible-community.github.io/awx-operator-helm/

  echo "Updating Helm repositories..."
  helm repo update

  # echo "Creating Kubernetes namespace for AWX..."
  # kubectl create namespace "$AWX_NAMESPACE" || true

  echo "Installing AWX Operator..."
  helm upgrade --install ansible-awx-operator awx-operator/awx-operator \
    --namespace "$AWX_NAMESPACE" --version "$AWX_OPERATOR_VERSION" \
    --set serviceType="$AWX_SERVICE_TYPE" --create-namespace

  echo "Waiting for AWX CRD to be available..."
  until kubectl get crd awxs.awx.ansible.com &>/dev/null; do
    echo "AWX CRD not available yet. Waiting..."
    sleep 5
  done

  echo "Deploying AWX instance..."
  kubectl apply -f - <<EOF
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx
  namespace: $AWX_NAMESPACE
spec:
  service_type: $AWX_SERVICE_TYPE
  web_resource_requirements:
    requests:
      memory: "4Gi"
      cpu: "4"
    limits:
      memory: "4Gi"
      cpu: "4"
  task_resource_requirements:
    requests:
      memory: "8Gi"
      cpu: "8"
    limits:
      memory: "16Gi"
      cpu: "16"
  ee_resource_requirements:
    requests:
      memory: "4Gi"
      cpu: "4"
    limits:
      memory: "4Gi"
      cpu: "4"
EOF

  echo "Waiting for AWX services to be ready..."
  sleep 600  # Adjust sleep time as necessary

echo "Creating PVC for Ansible Runner..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ansible-runner-pvc
  namespace: $AWX_NAMESPACE
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 100Gi
EOF

echo "Deploying Ansible Runner..."
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ansible-runner
  namespace: $AWX_NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ansible-runner
  template:
    metadata:
      labels:
        app: ansible-runner
    spec:
      imagePullSecrets:
      - name: docker-hub-registry-secret
      containers:
      - name: ansible-runner-container
        image: $ANSIBLE_RUNNER_IMAGE
        ports:
        - containerPort: 22
        securityContext:
          capabilities:
            add:
            - NET_ADMIN
            - SYS_ADMIN
          runAsUser: 0
        volumeMounts:
        - mountPath: /data
          name: ansible-runner-storage
      dnsPolicy: ClusterFirst
      hostAliases:
      - ip: "127.0.0.1"
        hostnames:
        - "$RUNNER_DNS"
      volumes:
      - name: ansible-runner-storage
        persistentVolumeClaim:
          claimName: ansible-runner-pvc
EOF

echo "Deploying Ansible Runner Service..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: ansible-runner
  namespace: $AWX_NAMESPACE
spec:
  selector:
    app: ansible-runner
  ports:
  - protocol: TCP
    port: 22
    targetPort: 22
  type: ClusterIP
EOF


  echo "Waiting for admin password to be available..."
  while true; do
    AWX_ADMIN_PASSWORD=$(kubectl get secret awx-admin-password -n "$AWX_NAMESPACE" -o jsonpath='{.data.password}' | base64 --decode 2>/dev/null || true)
    if [[ -n "$AWX_ADMIN_PASSWORD" ]]; then
      echo "Admin password retrieved: $AWX_ADMIN_PASSWORD"
      break
    fi
    echo "Admin password not available yet. Waiting..."
    sleep 5
  done

  echo "Waiting for AWX pod to be running..."
  while true; do
    POD_NAME=$(kubectl get pod -n "$AWX_NAMESPACE" -l "app.kubernetes.io/name=awx-web" -o jsonpath="{.items[0].metadata.name}" 2>/dev/null || true)
    if [[ -n "$POD_NAME" ]]; then
      POD_STATUS=$(kubectl get pod "$POD_NAME" -n "$AWX_NAMESPACE" -o jsonpath="{.status.phase}")
      if [[ "$POD_STATUS" == "Running" ]]; then
        echo "AWX pod is running."
        break
      fi
    else
      echo "AWX pod is not yet created. Waiting..."
    fi
    sleep 5
  done

  echo "Fetching AWX Node IP and Port..."
  NODE_IP=$(kubectl get pod -n "$AWX_NAMESPACE" -l app.kubernetes.io/name=awx-web -o jsonpath='{.items[0].status.hostIP}')
  NODE_PORT=$(kubectl get svc -n "$AWX_NAMESPACE" awx-service -o jsonpath='{.spec.ports[0].nodePort}')
  echo "AWX Node IP: $NODE_IP"
  echo "AWX Node Port: $NODE_PORT"

  echo "AWX Host URL: http://$NODE_IP:$NODE_PORT"

  echo "Waiting an additional 240 seconds for AWX to be fully operational..."
  sleep 240

  echo "Generating AWX Admin API Token..."
  AWX_HOST="http://$NODE_IP:$NODE_PORT"

  # Step 1: Generate API token using basic authentication
  TOKEN_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
    -u "$AWX_ADMIN_USER:$AWX_ADMIN_PASSWORD" \
    "$AWX_HOST/api/v2/tokens/")

  # Extract the token from the response
  AWX_API_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.token')

  if [[ -n "$AWX_API_TOKEN" && "$AWX_API_TOKEN" != "null" ]]; then
    echo "AWX Admin API Token: $AWX_API_TOKEN"
  else
    echo "Failed to generate AWX Admin API token"
    echo "Response: $TOKEN_RESPONSE"
    exit 1
  fi

  echo "AWX deployment complete."
}

# Function to set up AWX resources
setup_awx_resources() {
  echo "Setting up AWX resources..."

  # Function to create an inventory
  create_inventory() {
    echo "Creating inventory: $INVENTORY_NAME..."
    RESPONSE=$(curl -s -X POST "$AWX_HOST/api/v2/inventories/" \
      -H "Authorization: Bearer $AWX_API_TOKEN" \
      -H "Content-Type: application/json" \
      -d '{
        "name": "'"${INVENTORY_NAME}"'",
        "description": "'"${INVENTORY_DESCRIPTION}"'",
        "organization": '"$ORGANIZATION_ID"'
      }')

    # echo "Response: $RESPONSE"  # Debugging output

    INVENTORY_ID=$(echo "$RESPONSE" | jq -r '.id')
    if [[ -z "$INVENTORY_ID" || "$INVENTORY_ID" == "null" ]]; then
      echo "Error: Failed to create inventory."
      exit 1
    fi

    echo "Inventory created successfully with ID: $INVENTORY_ID"
  }

  # Function to add a host to the inventory
  add_host() {
    echo "Adding host to inventory..."
    RESPONSE=$(curl -s -X POST "$AWX_HOST/api/v2/hosts/" \
      -H "Authorization: Bearer $AWX_API_TOKEN" \
      -H "Content-Type: application/json" \
      -d '{
        "name": "'"$RUNNER_DNS"'",
        "description": "Ansible Runner Host",
        "inventory": '"$INVENTORY_ID"'
      }')

    # echo "Response: $RESPONSE"  # Debugging output

    HOST_ID=$(echo "$RESPONSE" | jq -r '.id')
    if [[ -z "$HOST_ID" || "$HOST_ID" == "null" ]]; then
      echo "Error: Failed to add host to inventory."
      exit 1
    fi

    echo "Host added successfully with ID: $HOST_ID"
  }

  # Function to fetch SSH credential type ID
  get_machine_credential_type_id() {
    echo "Fetching Machine credential type ID..."
    RESPONSE=$(curl -s -X GET "$AWX_HOST/api/v2/credential_types/?name=Machine" \
      -H "Authorization: Bearer $AWX_API_TOKEN")

    # echo "Response: $RESPONSE"  # Debugging output

    MACHINE_CRED_TYPE=$(echo "$RESPONSE" | jq -r '.results[0].id')
    if [[ -z "$MACHINE_CRED_TYPE" || "$MACHINE_CRED_TYPE" == "null" ]]; then
      echo "Error: Could not retrieve Machine credential type ID."
      exit 1
    fi

    echo "Machine credential type ID: $MACHINE_CRED_TYPE"
  }

  # Function to add SSH credential
  add_ssh_credential() {
    echo "Adding SSH credential..."
    
    # Wait for the ansible-runner pod to be ready
    while true; do
      RUNNER_POD=$(kubectl get pod -n "${AWX_NAMESPACE}" -l app=ansible-runner -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
      if [[ -n "$RUNNER_POD" ]]; then
        break
      else
        echo "Ansible Runner pod not found. Waiting..."
        sleep 5
      fi
    done

    # Copy the SSH private key from the pod
    kubectl cp -c ansible-runner-container "${AWX_NAMESPACE}/$RUNNER_POD:/root/.ssh/id_rsa" /tmp/id_rsa_runner

    if [[ -f /tmp/id_rsa_runner ]]; then
      SSH_KEY_DATA=$(awk '{printf "%s\\n", $0}' /tmp/id_rsa_runner)
      rm /tmp/id_rsa_runner  # Clean up the temporary file

      # Create the SSH credential in AWX
      RESPONSE=$(curl -s -X POST "$AWX_HOST/api/v2/credentials/" \
        -H "Authorization: Bearer $AWX_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
          "name": "SSH Key for Ansible Runner",
          "description": "Private SSH key for connecting to the runner",
          "organization": '"${ORGANIZATION_ID}"',
          "credential_type": '"${MACHINE_CRED_TYPE}"',
          "inputs": {
              "username": "root",
              "ssh_key_data": "'"$SSH_KEY_DATA"'"
          }
        }')

      # echo "Response: $RESPONSE"  # Debugging output

      SSH_CRED_ID=$(echo "$RESPONSE" | jq -r '.id')
      if [[ -z "$SSH_CRED_ID" || "$SSH_CRED_ID" == "null" ]]; then
        echo "Error: Failed to create SSH credential."
        exit 1
      fi

      echo "SSH credential added with ID: $SSH_CRED_ID"
    else
      echo "Error: SSH private key not found after copying"
      exit 1
    fi
  }


  # Function to create GitHub credentials
add_github_credential() {
    echo "Adding GitHub OAuth credential..."

    # Build the JSON payload and store it in a variable for better debugging
    JSON_PAYLOAD=$(cat <<EOF
{
  "name": "${GITHUB_CRED_NAME}",
  "description": "GitHub OAuth token for accessing repos",
  "organization": ${ORGANIZATION_ID},
  "credential_type": 2,
  "inputs": {
    "username": "${GITHUB_USERNAME}",
    "password": "${GITHUB_TOKEN}"
  }
}
EOF
)

    # # Debugging: print out the JSON payload
    # echo "JSON Payload: $JSON_PAYLOAD"

    # Make the API call
    RESPONSE=$(curl -s -X POST "$AWX_HOST/api/v2/credentials/" \
      -H "Authorization: Bearer $AWX_API_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$JSON_PAYLOAD")

    # echo "Response: $RESPONSE"  # Debugging output

    # Extract the credential ID from the response
    GITHUB_CRED_ID=$(echo "$RESPONSE" | jq -r '.id')
    if [[ -z "$GITHUB_CRED_ID" || "$GITHUB_CRED_ID" == "null" ]]; then
      echo "Error: Failed to create GitHub credential."
      exit 1
    fi

    echo "GitHub credential added with ID: $GITHUB_CRED_ID"
}


  # Function to create a project
  create_project() {
    echo "Creating project: $PROJECT_NAME..."
    RESPONSE=$(curl -s -X POST "$AWX_HOST/api/v2/projects/" \
      -H "Authorization: Bearer $AWX_API_TOKEN" \
      -H "Content-Type: application/json" \
      -d '{
        "name": "'"${PROJECT_NAME}"'",
        "description": "'"${PROJECT_DESCRIPTION}"'",
        "organization": '"$ORGANIZATION_ID"',
        "scm_type": "git",
        "scm_url": "'"${GITHUB_REPO_URL}"'",
        "scm_branch": "prod",
        "credential": '"$GITHUB_CRED_ID"',
        "scm_clean": true,
        "scm_update_on_launch": true
      }')

    # echo "Response: $RESPONSE"  # Debugging output

    PROJECT_ID=$(echo "$RESPONSE" | jq -r '.id')
    if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "null" ]]; then
      echo "Error: Failed to create project."
      exit 1
    fi

    echo "Project created successfully with ID: $PROJECT_ID"
    echo "sleep 60 seconds"
    sleep 60

  }

  # Execute the resource setup functions in order
  create_inventory
  add_host
  get_machine_credential_type_id
  add_ssh_credential
  add_github_credential
  create_project

  echo "AWX resources setup complete."
}


# ----------------------------- #
#           Main Execution      #
# ----------------------------- #

main() {
  install_dependencies
  install_awx
  setup_awx_resources
  echo "All tasks completed successfully."
  echo "AWX Node IP: $NODE_IP"
  echo "AWX Node Port: $NODE_PORT"
  echo "AWX Host URL: http://$NODE_IP:$NODE_PORT"
  echo "Admin password retrieved: $AWX_ADMIN_PASSWORD"
  echo "AWX Admin API Token: $AWX_API_TOKEN"
  echo "GitHub credential added with ID: $GITHUB_CRED_ID"
  echo "SSH credential added with ID: $SSH_CRED_ID"
  echo "Inventory created successfully with ID: $INVENTORY_ID"
  echo "Host added successfully with ID: $HOST_ID"
  echo "Project created successfully with ID: $PROJECT_ID"
}

# Invoke the main function
main
