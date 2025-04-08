#!/bin/bash

# AWX Configuration
NODE_IP=10.10.10.19
NODE_PORT=31120
AWX_ADMIN_TOKEN=xxxxxx
SCHEDULE_NAME="Daily Backup Schedule"  # Name for the schedule

# Step 1: Get all Job Templates
echo "Retrieving all job templates..."

JOB_TEMPLATES=$(curl -s -X GET "http://${NODE_IP}:${NODE_PORT}/api/v2/job_templates/" \
  -H "Authorization: Bearer ${AWX_ADMIN_TOKEN}" \
  -H "Content-Type: application/json" | jq -r '.results[] | {id: .id, name: .name}')

if [ -z "$JOB_TEMPLATES" ]; then
  echo "No job templates found."
  exit 0
fi

# Display retrieved templates
echo "Job Templates:"
echo "$JOB_TEMPLATES"