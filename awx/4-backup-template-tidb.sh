#!/bin/bash

# Fail on any error
set -ex

# Variables (replace with actual values or set as environment variables)
NODE_IP=10.10.10.19
NODE_PORT=31120
AWX_ADMIN_TOKEN=xxxxxx
INVENTORY_ID=2
PROJECT_ID=8
MACHINE_CREDENTIAL_ID=3


TEMPLATE_NAME="TiDB-ctrls-hyd-db-Backup"
PLAYBOOK="playbook-backup-tidb.yaml"
AZ_BLOB_URL="https://prodmobiusdbbkp.blob.core.windows.net/mysqlmanaged"
AZ_BLOB_TOKEN="sv=xxxxx"

# TiDB-specific vars
TIDB_HOST="basic-tidb.tidb-cluster.svc.cluster.local"
TIDB_PORT=4000
TIDB_USER="root"
TIDB_PASSWORD="GaianMobius"
BASE_BACKUP_DIR="/data/tidb"
EXCLUDE_DBS="INFORMATION_SCHEMA METRICS_SCHEMA mysql PERFORMANCE_SCHEMA test"

# Email notification settings
SMTP_SERVER="smtp.gmail.com"
SMTP_PORT=587
SMTP_USERNAME="alerts@mobiusdtaas.ai"
SMTP_PASSWORD="Gaian123456789"
EMAIL_SENDER="alerts@mobiusdtaas.ai"
EMAIL_RECIPIENTS="devops@mobiusdtaas.ai"

# Generate extra_vars JSON string using jq
extra_vars_json=$(jq -n \
  --arg az_blob_url "$AZ_BLOB_URL" \
  --arg az_blob_token "$AZ_BLOB_TOKEN" \
  --arg tidb_host "$TIDB_HOST" \
  --arg tidb_port "$TIDB_PORT" \
  --arg tidb_user "$TIDB_USER" \
  --arg tidb_password "$TIDB_PASSWORD" \
  --arg base_backup_dir "$BASE_BACKUP_DIR" \
  --arg exclude_dbs "$EXCLUDE_DBS" \
  --arg smtp_server "$SMTP_SERVER" \
  --arg smtp_port "$SMTP_PORT" \
  --arg smtp_username "$SMTP_USERNAME" \
  --arg smtp_password "$SMTP_PASSWORD" \
  --arg email_sender "$EMAIL_SENDER" \
  --arg email_recipients "$EMAIL_RECIPIENTS" \
  '{
    az_blob_url: $az_blob_url,
    az_blob_token: $az_blob_token,
    tidb_host: $tidb_host,
    tidb_port: $tidb_port,
    tidb_user: $tidb_user,
    tidb_password: $tidb_password,
    base_backup_dir: $base_backup_dir,
    exclude_dbs: $exclude_dbs,
    smtp_server: $smtp_server,
    smtp_port: $smtp_port,
    smtp_username: $smtp_username,
    smtp_password: $smtp_password,
    email_sender: $email_sender,
    email_recipients: $email_recipients
  }' | jq -c .)

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

# Step 2: Create the job template with additional vars
JOB_TEMPLATE_RESPONSE=$(curl -s -X POST "http://${NODE_IP}:${NODE_PORT}/api/v2/job_templates/" \
  -H "Authorization: Bearer ${AWX_ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "'"${TEMPLATE_NAME}"'",
    "description": "This is a job template for TiDB backup with machine credentials",
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
  -d '{
    "id": '"${MACHINE_CREDENTIAL_ID}"'
  }')

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
