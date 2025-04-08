#!/bin/bash

# AWX server configuration
NODE_IP=172.16.30.21  # AWX server IP
NODE_PORT=31649  # AWX server Port
AWX_ADMIN_TOKEN="xxxxx"  # AWX Admin Token

# Job Template IDs to delete (you can add more IDs separated by space)
JOB_TEMPLATE_IDS=("10" "11" "12")  # Replace with your job template IDs as needed

echo "Deleting the specified job templates by ID..."

# Step 1: Delete the selected job templates
for JOB_ID in "${JOB_TEMPLATE_IDS[@]}"
do
  JOB_ID=$(echo "$JOB_ID" | xargs)  # Trim whitespaces
  echo "Deleting Job Template ID: $JOB_ID"

  DELETE_RESPONSE=$(curl -s -X DELETE "http://${NODE_IP}:${NODE_PORT}/api/v2/job_templates/$JOB_ID/" \
    -H "Authorization: Bearer ${AWX_ADMIN_TOKEN}" \
    -H "Content-Type: application/json")

  # Check if the job template was deleted successfully
  if [ -z "$DELETE_RESPONSE" ]; then
    echo "Successfully deleted Job Template ID: $JOB_ID"
  else
    echo "Failed to delete Job Template ID: $JOB_ID"
    echo "Response: $DELETE_RESPONSE"
  fi
done

echo "All specified job templates have been processed for deletion."
