#!/bin/bash

# AWX Configuration
NODE_IP=10.10.10.19
NODE_PORT=31120
AWX_ADMIN_TOKEN=xxxxxx
SCHEDULE_NAME="Daily Backup Schedule"  # Name for the schedule
JOB_TEMPLATE_IDS=("12" "11" "9")  # Replace with your job template IDs

# Step 1: Schedule the specified Job Templates by ID
echo "Scheduling the specified job templates by ID..."

for TEMPLATE_ID in "${JOB_TEMPLATE_IDS[@]}"; do
  TEMPLATE_ID=$(echo "$TEMPLATE_ID" | xargs)  # Remove leading/trailing whitespaces

  # Retrieve template details to get template name
  TEMPLATE_RESPONSE=$(curl -s -X GET "http://${NODE_IP}:${NODE_PORT}/api/v2/job_templates/${TEMPLATE_ID}/" \
    -H "Authorization: Bearer ${AWX_ADMIN_TOKEN}" \
    -H "Content-Type: application/json")

  # Extract template name from the response
  TEMPLATE_NAME=$(echo "$TEMPLATE_RESPONSE" | jq -r '.name')

  if [ "$TEMPLATE_NAME" = "null" ]; then
    echo "Template with ID '$TEMPLATE_ID' not found. Skipping..."
    continue
  fi

  echo "Scheduling Job Template: $TEMPLATE_NAME (ID: $TEMPLATE_ID)"

  # Create a schedule for the template #To set the time to 12:00 AM every day in the RRULE, you should update the DTSTART time to match 12:00 AM (0000 hours in 24-hour format) and keep the rest of the rule the same.
  SCHEDULE_RESPONSE=$(curl -s -X POST "http://${NODE_IP}:${NODE_PORT}/api/v2/job_templates/${TEMPLATE_ID}/schedules/" \
    -H "Authorization: Bearer ${AWX_ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{
          "name": "'"${SCHEDULE_NAME}"'",
          "description": "Daily schedule for job template '"${TEMPLATE_NAME}"'",
          "rrule": "DTSTART;TZID=Asia/Kolkata:20240105T000000\nRRULE:FREQ=DAILY;INTERVAL=1",
          "enabled": true,
          "timezone": "Asia/Kolkata"
        }')



  if echo "$SCHEDULE_RESPONSE" | grep -q '"id":'; then
    echo "Schedule created successfully for $TEMPLATE_NAME."

    # Extract the schedule ID from the response
    SCHEDULE_ID=$(echo "$SCHEDULE_RESPONSE" | jq -r '.id')

    # Verify the newly created schedule
    VERIFY_SCHEDULE_RESPONSE=$(curl -s -X GET "http://${NODE_IP}:${NODE_PORT}/api/v2/schedules/${SCHEDULE_ID}/" \
      -H "Authorization: Bearer ${AWX_ADMIN_TOKEN}" \
      -H "Content-Type: application/json")

    if echo "$VERIFY_SCHEDULE_RESPONSE" | grep -q '"name": "'"${SCHEDULE_NAME}"'"'; then
      echo "Verified: Schedule '$SCHEDULE_NAME' exists for Job Template '$TEMPLATE_NAME'."
    else
      echo "Verification failed for schedule '$SCHEDULE_NAME' for Job Template '$TEMPLATE_NAME'."
    fi

  else
    echo "Failed to create schedule for $TEMPLATE_NAME. Response: $SCHEDULE_RESPONSE"
  fi
done

echo "Specified templates have been processed for scheduling."
