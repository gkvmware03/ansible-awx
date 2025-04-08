#!/bin/bash

# AWX server configuration
NODE_IP=10.11.7.206  # AWX server IP
NODE_PORT=30897  # AWX server Port
AWX_ADMIN_TOKEN="xxxx"  # AWX Admin Token

# Job Template IDs to update
JOB_TEMPLATE_IDS=("9" "10" "11")  # Replace with your job template IDs

# The variable to replace and its new value
VAR_TO_REPLACE="email_recipients"
NEW_VALUE="kota.g@mobiusdtaas.ai,mulagapati.d@mobiusdtaas.ai,sutrapu.s@mobiusdtaas.ai,medishetty.g@mobiusdtaas.ai,upadhyay.p@mobiusdtaas.ai,selvan.v@mobiusdtaas.ai,karri.v@mobiusdtaas.ai,kurra.b@mobiusdtaas.ai"

echo "Replacing variable '${VAR_TO_REPLACE}' with new value for the specified job templates..."

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

  # Convert existing extra_vars to JSON format
  EXISTING_EXTRA_VARS_JSON=$(echo "$EXISTING_EXTRA_VARS" | jq -c .)

  # Replace or add the specific variable's value
  UPDATED_EXTRA_VARS=$(echo "$EXISTING_EXTRA_VARS_JSON" | jq --arg key "$VAR_TO_REPLACE" --arg newValue "$NEW_VALUE" '.[$key] = $newValue')

  # Convert the updated extra_vars to a properly escaped JSON string for the payload
  UPDATED_EXTRA_VARS_ESCAPED=$(echo "$UPDATED_EXTRA_VARS" | jq -c @json)

  # Update the job template with the new merged extra_vars
  UPDATE_RESPONSE=$(curl -s -X PATCH "http://${NODE_IP}:${NODE_PORT}/api/v2/job_templates/$JOB_ID/" \
    -H "Authorization: Bearer ${AWX_ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{
          "extra_vars": '"$UPDATED_EXTRA_VARS_ESCAPED"'
        }')

  # Check if the extra_vars were updated successfully
  if echo "$UPDATE_RESPONSE" | jq -e .id > /dev/null; then
    echo "Successfully updated extra_vars for Job Template ID: $JOB_ID"
  else
    echo "Failed to update extra_vars for Job Template ID: $JOB_ID"
    echo "Response: $UPDATE_RESPONSE"
  fi
done

echo "All specified job templates have been processed for updating extra vars."
