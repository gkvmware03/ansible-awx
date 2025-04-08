#!/bin/bash

# Define your variables here
NODE_IP=10.10.10.19
NODE_PORT=31120
AWX_ADMIN_TOKEN=xxxxx
INVENTORY_ID=2
PROJECT_ID=8
MACHINE_CREDENTIAL_ID=3
TEMPLATE_NAME=mongodb-ctrls-hyd-backup
PLAYBOOK=playbook-backup-mongo.yaml

AZ_BLOB_URL="https://prodmobiusdbbkp.blob.core.windows.net/mongodb"
AZ_BLOB_TOKEN="sv=xxx"

MONGODB_HOST="percona-mongodb-db-ps-rs0.percona.svc.cluster.local"
MONGODB_PORT=27017
MONGODB_USER="gaian"
MONGODB_PASSWORD="GaianMobius"
MONGODB_AUTH_DB="admin"
REPLICASET="rs0"
BASE_BACKUP_DIR="/data/mongodb"
EXCLUDE_DBS="admin local config"
ENCRYPTION_PASSWORD="GaianMobius231"
SMTP_SERVER="smtp.gmail.com"
SMTP_PORT=587
SMTP_USERNAME="alerts@mobiusdtaas.ai"
SMTP_PASSWORD="Gaian123456789"
EMAIL_SENDER="alerts@mobiusdtaas.ai"
EMAIL_RECIPIENTS="devops@mobiusdtaas.ai"

# Step 1: Check if the job template already exists
EXISTING_TEMPLATE=$(curl -s -X GET "http://${NODE_IP}:${NODE_PORT}/api/v2/job_templates/?name=${TEMPLATE_NAME}" \
  -H "Authorization: Bearer ${AWX_ADMIN_TOKEN}" \
  -H "Content-Type: application/json" | jq -r '.results | length')

if [ "$EXISTING_TEMPLATE" -gt 0 ]; then
  echo "Job template already exists. Skipping creation."
  # Retrieve the existing job template ID
  JOB_TEMPLATE_ID=$(curl -s -X GET "http://${NODE_IP}:${NODE_PORT}/api/v2/job_templates/?name=${TEMPLATE_NAME}" \
    -H "Authorization: Bearer ${AWX_ADMIN_TOKEN}" \
    -H "Content-Type: application/json" | jq -r '.results[0].id')
  echo "Existing Job Template ID: $JOB_TEMPLATE_ID"
  echo "job_template_id=$JOB_TEMPLATE_ID" > /tmp/job_template.txt
  exit 0
fi


# Generate extra_vars JSON string using jq
extra_vars_json=$(jq -n \
  --arg az_blob_url "$AZ_BLOB_URL" \
  --arg az_blob_token "$AZ_BLOB_TOKEN" \
  --arg mongodb_host "$MONGODB_HOST" \
  --arg mongodb_port "$MONGODB_PORT" \
  --arg mongodb_user "$MONGODB_USER" \
  --arg mongodb_password "$MONGODB_PASSWORD" \
  --arg mongodb_auth_db "$MONGODB_AUTH_DB" \
  --arg replicaset "$REPLICASET" \
  --arg base_backup_dir "$BASE_BACKUP_DIR" \
  --arg exclude_dbs "$EXCLUDE_DBS" \
  --arg smtp_server "$SMTP_SERVER" \
  --arg smtp_port "$SMTP_PORT" \
  --arg smtp_username "$SMTP_USERNAME" \
  --arg smtp_password "$SMTP_PASSWORD" \
  --arg email_sender "$EMAIL_SENDER" \
  --arg encryption_password "$ENCRYPTION_PASSWORD" \
  --arg email_recipients "$EMAIL_RECIPIENTS" \
  '{
    az_blob_url: $az_blob_url,
    az_blob_token: $az_blob_token,
    mongodb_host: $mongodb_host,
    mongodb_port: $mongodb_port,
    mongodb_user: $mongodb_user,
    mongodb_password: $mongodb_password,
    mongodb_auth_db: $mongodb_auth_db,
    replicaset: $replicaset,
    base_backup_dir: $base_backup_dir,
    exclude_dbs: $exclude_dbs,
    smtp_server: $smtp_server,
    smtp_port: $smtp_port,
    smtp_username: $smtp_username,
    smtp_password: $smtp_password,
    email_sender: $email_sender,
    encryption_password: $encryption_password,
    email_recipients: $email_recipients
  }' | jq -c .)

# Step 2: Create the job template with additional vars
JOB_TEMPLATE_RESPONSE=$(curl -s -X POST "http://${NODE_IP}:${NODE_PORT}/api/v2/job_templates/" \
  -H "Authorization: Bearer ${AWX_ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "'"${TEMPLATE_NAME}"'",
    "description": "This is a job template for MongoDB backup with machine credentials",
    "job_type": "run",
    "inventory": '"${INVENTORY_ID}"',
    "project": '"${PROJECT_ID}"',
    "playbook": "'"${PLAYBOOK}"'",
    "verbosity": 1,
    "extra_vars": '"$(echo $extra_vars_json | jq -R .)"'
  }')

# Log the response for debugging
echo "Job Template Response: $JOB_TEMPLATE_RESPONSE"

# Step 3: Extract Job Template ID
JOB_TEMPLATE_ID=$(echo "$JOB_TEMPLATE_RESPONSE" | jq -r '.id')

if [ -z "$JOB_TEMPLATE_ID" ] || [ "$JOB_TEMPLATE_ID" = "null" ]; then
  echo "Error: Could not create Job Template."
  echo "Full Response: $JOB_TEMPLATE_RESPONSE"
  exit 1
fi

echo "Job Template ID: $JOB_TEMPLATE_ID"


# Step 4: Attach credentials to the job template
ATTACH_CREDENTIAL_RESPONSE=$(curl -s -X POST "http://${NODE_IP}:${NODE_PORT}/api/v2/job_templates/$JOB_TEMPLATE_ID/credentials/" \
  -H "Authorization: Bearer ${AWX_ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"id\": ${MACHINE_CREDENTIAL_ID}}")

echo "Attach Credential Response: $ATTACH_CREDENTIAL_RESPONSE"

# Step 5: Verify the credentials in the job template (GET) with retry logic
MAX_RETRIES=5
RETRY_COUNT=0
CREDENTIAL_ATTACHED=false

while [ "$RETRY_COUNT" -lt "$MAX_RETRIES" ]; do
  JOB_TEMPLATE_VERIFY=$(curl -s -X GET "http://${NODE_IP}:${NODE_PORT}/api/v2/job_templates/$JOB_TEMPLATE_ID/" \
    -H "Authorization: Bearer ${AWX_ADMIN_TOKEN}" \
    -H "Content-Type: application/json")

  # Check if credentials are successfully attached
  CREDENTIAL_COUNT=$(echo "$JOB_TEMPLATE_VERIFY" | jq '.summary_fields.credentials | length')

  if [ "$CREDENTIAL_COUNT" -gt 0 ]; then
    CREDENTIAL_ATTACHED=true
    echo "Credentials successfully attached."
    break
  else
    echo "Credentials not attached yet, retrying... ($RETRY_COUNT/$MAX_RETRIES)"
    RETRY_COUNT=$((RETRY_COUNT+1))
    sleep 10
  fi
done

if [ "$CREDENTIAL_ATTACHED" = false ]; then
  echo "Error: Failed to attach credentials after $MAX_RETRIES retries."
  exit 1
fi

# Save the job template ID for further use
echo "job_template_id=$JOB_TEMPLATE_ID" > /tmp/job_template.txt
