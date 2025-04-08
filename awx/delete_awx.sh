#!/bin/bash
set -euo pipefail

# ----------------------------- #
#          Configuration        #
# ----------------------------- #

# AWX Installation Variables
AWX_NAMESPACE="awx"
AWX_OPERATOR_VERSION="2.12.0"
AWX_ADMIN_USER="admin"
AWX_HOST="http://10.10.10.19:32516"  # Modify if you have static IPs and ports
AWX_API_TOKEN="xxxx"  # Should be set to the value retrieved earlier

# ----------------------------- #
#          Helper Functions     #
# ----------------------------- #




# Function to retrieve resource IDs
get_awx_resource_ids() {
  echo "Retrieving AWX resource IDs..."

  # Get Project ID
  PROJECT_ID=$(curl -s -X GET "$AWX_HOST/api/v2/projects/" \
    -H "Authorization: Bearer $AWX_API_TOKEN" | jq -r '.results[0].id')
  
  # Get GitHub Credential ID
  GITHUB_CRED_ID=$(curl -s -X GET "$AWX_HOST/api/v2/credentials/?name=DurgaPrasad%20GitHub%20Token" \
    -H "Authorization: Bearer $AWX_API_TOKEN" | jq -r '.results[0].id')

  # Get SSH Credential ID
  SSH_CRED_ID=$(curl -s -X GET "$AWX_HOST/api/v2/credentials/?name=SSH%20Key%20for%20Ansible%20Runner" \
    -H "Authorization: Bearer $AWX_API_TOKEN" | jq -r '.results[0].id')

  # Get Inventory ID
  INVENTORY_ID=$(curl -s -X GET "$AWX_HOST/api/v2/inventories/?name=AWX%20Runner" \
    -H "Authorization: Bearer $AWX_API_TOKEN" | jq -r '.results[0].id')

  # Get Host ID
  HOST_ID=$(curl -s -X GET "$AWX_HOST/api/v2/hosts/?name=ansible-runner.awx.svc.cluster.local" \
    -H "Authorization: Bearer $AWX_API_TOKEN" | jq -r '.results[0].id')

  echo "AWX resource IDs retrieved successfully."
}

# Function to delete AWX resources using API calls
delete_awx_resources() {
  echo "Deleting AWX resources via API..."

  # Delete project
  echo "Deleting project with ID: $PROJECT_ID..."
  curl -s -X DELETE "$AWX_HOST/api/v2/projects/$PROJECT_ID/" \
    -H "Authorization: Bearer $AWX_API_TOKEN" \
    -H "Content-Type: application/json"

  # Delete GitHub credential
  echo "Deleting GitHub credential with ID: $GITHUB_CRED_ID..."
  curl -s -X DELETE "$AWX_HOST/api/v2/credentials/$GITHUB_CRED_ID/" \
    -H "Authorization: Bearer $AWX_API_TOKEN" \
    -H "Content-Type: application/json"

  # Delete SSH credential
  echo "Deleting SSH credential with ID: $SSH_CRED_ID..."
  curl -s -X DELETE "$AWX_HOST/api/v2/credentials/$SSH_CRED_ID/" \
    -H "Authorization: Bearer $AWX_API_TOKEN" \
    -H "Content-Type: application/json"

  # Delete inventory
  echo "Deleting inventory with ID: $INVENTORY_ID..."
  curl -s -X DELETE "$AWX_HOST/api/v2/inventories/$INVENTORY_ID/" \
    -H "Authorization: Bearer $AWX_API_TOKEN" \
    -H "Content-Type: application/json"

  # Delete hosts
  echo "Deleting host with ID: $HOST_ID..."
  curl -s -X DELETE "$AWX_HOST/api/v2/hosts/$HOST_ID/" \
    -H "Authorization: Bearer $AWX_API_TOKEN" \
    -H "Content-Type: application/json"

  echo "AWX resources deleted successfully."
}

# Function to delete AWX instance and its components
delete_awx_instance() {
  echo "Deleting AWX instance..."

  # Delete the AWX instance
  echo "Deleting AWX instance in namespace $AWX_NAMESPACE..."
  kubectl delete awx awx -n "$AWX_NAMESPACE"

  # Delete the AWX Operator
  echo "Deleting AWX Operator Helm release..."
  helm uninstall ansible-awx-operator --namespace "$AWX_NAMESPACE"

  echo "AWX instance deleted."
}

# Function to delete PVCs, deployments, and services
delete_k8s_resources() {
  echo "Deleting Kubernetes resources..."

  # Delete Ansible Runner deployment and service
  echo "Deleting Ansible Runner Deployment..."
  kubectl delete deployment ansible-runner -n "$AWX_NAMESPACE"

  echo "Deleting Ansible Runner Service..."
  kubectl delete service ansible-runner -n "$AWX_NAMESPACE"

  # Delete PersistentVolumeClaims
  echo "Deleting PersistentVolumeClaim..."
  kubectl delete pvc ansible-runner-pvc -n "$AWX_NAMESPACE"

  # Optionally delete the namespace
  echo "Deleting AWX namespace..."
  kubectl delete namespace "$AWX_NAMESPACE"

  echo "Kubernetes resources deleted."
}

# ----------------------------- #
#           Main Execution      #
# ----------------------------- #

main() {
  get_awx_resource_ids
  delete_awx_resources
  delete_awx_instance
  delete_k8s_resources
  echo "AWX and all associated resources have been deleted."
}

# Invoke the main function
main
