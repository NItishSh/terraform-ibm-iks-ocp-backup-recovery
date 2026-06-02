#!/bin/bash
# Common utility functions for BRS scripts

# Get IAM token from IBM Cloud.
# Usage: get_iam_token API_KEY ENDPOINT_TYPE
# Returns: IAM access token
#
# Prefers the IAM_TOKEN environment variable when set (populated by the
# ibm_iam_auth_token Terraform data source for create-time provisioners).
# Falls back to an API key exchange via curl, which is used for token refresh
# during long-running polling and for destroy-time provisioners where Terraform
# data sources are not available.
# To force a fresh token exchange (e.g. during refresh), callers must
# `unset IAM_TOKEN` before invoking this function.
get_iam_token() {
  local api_key=$1
  local endpoint_type=$2

  if [[ -n "${IAM_TOKEN:-}" ]]; then
    echo "${IAM_TOKEN}"
    return 0
  fi

  local iam_endpoint="${IBMCLOUD_IAM_API_ENDPOINT:-iam.cloud.ibm.com}"
  iam_endpoint=${iam_endpoint#https://}

  if [[ "$iam_endpoint" == "iam.cloud.ibm.com" && "$endpoint_type" == "private" ]]; then
    iam_endpoint="private.${iam_endpoint}"
  fi

  local response
  response=$(curl --retry 3 -s -X POST "https://${iam_endpoint}/identity/token" \
    --header 'Content-Type: application/x-www-form-urlencoded' \
    --header 'Accept: application/json' \
    --data-urlencode 'grant_type=urn:ibm:params:oauth:grant-type:apikey' \
    --data-urlencode "apikey=${api_key}")  # pragma: allowlist secret

  if echo "$response" | jq -e 'has("errorMessage")' > /dev/null; then
    echo "IAM Error: $(echo "$response" | jq -r '.errorMessage')" >&2
    exit 1
  fi

  echo "$response" | jq -r '.access_token'
}
