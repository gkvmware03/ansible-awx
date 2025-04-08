#!/bin/bash

# AWX server configuration
NODE_IP=10.10.10.16  # AWX server IP
NODE_PORT=31964  # AWX server Port
AWX_ADMIN_TOKEN="xxxxxx"  # AWX Admin Token

# Job Template IDs to trigger (you can add more IDs separated by space)
JOB_TEMPLATE_IDS=("9")  # Replace with your job template IDs as needed

echo "Scheduling the specified job templates by ID..."

# Step 1: Trigger the selected job templates
for JOB_ID in "${JOB_TEMPLATE_IDS[@]}"
do
  JOB_ID=$(echo "$JOB_ID" | xargs)  # Trim whitespaces
  echo "Triggering job for Job Template ID: $JOB_ID"

  TRIGGER_RESPONSE=$(curl -s -X POST "http://${NODE_IP}:${NODE_PORT}/api/v2/job_templates/$JOB_ID/launch/" \
    -H "Authorization: Bearer ${AWX_ADMIN_TOKEN}" \
    -H "Content-Type: application/json")

  # Check if the job was triggered successfully
  JOB_LAUNCH_STATUS=$(echo "$TRIGGER_RESPONSE" | jq -r '.status // "failed"')

  if [ "$JOB_LAUNCH_STATUS" != "failed" ]; then
    echo "Successfully triggered Job Template ID: $JOB_ID"
  else
    echo "Failed to trigger Job Template ID: $JOB_ID"
    echo "Response: $TRIGGER_RESPONSE"
  fi
done

echo "All specified job templates have been processed for triggering."
