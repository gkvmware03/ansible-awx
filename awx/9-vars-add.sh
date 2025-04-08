#!/bin/bash

# AWX server configuration
NODE_IP=172.16.30.21  # AWX server IP
NODE_PORT=31649  # AWX server Port
AWX_ADMIN_TOKEN="xxxx"  # AWX Admin Token

# Job Template IDs to update
JOB_TEMPLATE_IDS=("10" "11" "12")  # Replace with your job template IDs

# Extra vars to add or replace (JSON format)
NEW_EXTRA_VARS='{
  "test1": "key1",
  "test2": "key22"
}'

echo "Updating the specified job templates with new extra vars..."

# Step 1: Update the extra_vars of the specified job templates
for JOB_ID in "${JOB_TEMPLATE_IDS[@]}"
do
  JOB_ID=$(echo "$JOB_ID" | xargs)  # Trim whitespaces
  echo "Updating Job Template ID: $JOB_ID"

  # Get the existing extra_vars for the template
  EXISTING_VARS_RESPONSE=$(curl -s -X GET "http://${NODE_IP}:${NODE_PORT}/api/v2/job_templates/$JOB_ID/" \
    -H "Authorization: Bearer ${AWX_ADMIN_TOKEN}" \
    -H "Content-Type: application/json")

  EXISTING_EXTRA_VARS=$(echo "$EXISTING_VARS_RESPONSE" | jq -r '.extra_vars')

  # Ensure EXISTING_EXTRA_VARS is a valid JSON object
  if [ "$EXISTING_EXTRA_VARS" == "null" ] || [ -z "$EXISTING_EXTRA_VARS" ]; then
    EXISTING_EXTRA_VARS="{}"
  fi

  # Merge the existing extra_vars with the new extra_vars
  UPDATED_EXTRA_VARS=$(echo "$EXISTING_EXTRA_VARS" | jq -c . | jq ". + $NEW_EXTRA_VARS")

  # Update the job template with the new merged extra_vars
  UPDATE_RESPONSE=$(curl -s -X PATCH "http://${NODE_IP}:${NODE_PORT}/api/v2/job_templates/$JOB_ID/" \
    -H "Authorization: Bearer ${AWX_ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"extra_vars\": $(echo "$UPDATED_EXTRA_VARS" | jq @json)}")

  # Check if the extra_vars were updated successfully
  if echo "$UPDATE_RESPONSE" | jq -e .id > /dev/null 2>&1; then
    echo "Successfully updated extra_vars for Job Template ID: $JOB_ID"
  else
    echo "Failed to update extra_vars for Job Template ID: $JOB_ID"
    echo "Response: $UPDATE_RESPONSE"
  fi
done

echo "All specified job templates have been processed for updating extra vars."
