#!/bin/sh

# Token Refresher - Updates Grafana datasources with fresh OAuth tokens
set -e

GRAFANA_URL="http://localhost:3000"
GRAFANA_USER="admin"
REFRESH_INTERVAL=${REFRESH_INTERVAL:-1800} # 30 minutes default

echo "Token Refresher starting..."
echo "Refresh interval: $REFRESH_INTERVAL seconds"

# Function to extract access token from JSON response without jq
get_oauth_token() {
    local token_response
    token_response=$(curl -s -H "Metadata-Flavor: Google" \
        "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token")
   
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to fetch OAuth token"
        return 1
    fi
    
    # Extract access_token using sed
    echo "$token_response" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p'
}

# Function to get Grafana admin password from environment variable
get_grafana_password() {
    if [ -n "$GRAFANA_ADMIN_PASSWORD" ]; then
        echo "$GRAFANA_ADMIN_PASSWORD"
    else
        echo "ERROR: GRAFANA_ADMIN_PASSWORD environment variable not set"
        return 1
    fi
}

# Function to update datasource
update_datasource() {
    local datasource_uid="$1"
    local datasource_name="$2"
    local project_id="$3"
    local token="$4"
    local is_default="$5"
    local password="$6"
    
    echo "Updating datasource: $datasource_name (UID: $datasource_uid)"
    
    local datasource_config="{
  \"uid\": \"$datasource_uid\",
  \"name\": \"$datasource_name\",
  \"type\": \"prometheus\",
  \"access\": \"proxy\",
  \"url\": \"https://monitoring.googleapis.com/v1/projects/$project_id/location/global/prometheus\",
  \"isDefault\": $is_default,
  \"editable\": true,
  \"jsonData\": {
    \"httpMethod\": \"POST\",
    \"queryTimeout\": \"300s\",
    \"timeInterval\": \"30s\",
    \"httpHeaderName1\": \"Authorization\"
  },
  \"secureJsonData\": {
    \"httpHeaderValue1\": \"Bearer $token\"
  }
}"
    
    # Update the datasource
    local response
    response=$(curl -s -w "%{http_code}" -o /tmp/grafana_response.json \
        -X PUT \
        -H "Content-Type: application/json" \
        -u "$GRAFANA_USER:$password" \
        -d "$datasource_config" \
        "$GRAFANA_URL/api/datasources/uid/$datasource_uid")
   
    local http_code=$(echo "$response" | tail -c 4)
    
    if [ "$http_code" = "200" ]; then
        echo "Successfully updated datasource: $datasource_name"
        return 0
    else
        echo "ERROR: Failed to update datasource: $datasource_name (HTTP $http_code)"
        if [ -f /tmp/grafana_response.json ]; then
            cat /tmp/grafana_response.json
        fi
        return 1
    fi
}

# Function to wait for Grafana to be ready
wait_for_grafana() {
    echo "Waiting for Grafana to be ready..."
    local max_attempts=30
    local attempt=1
    local password
    
    password=$(get_grafana_password)
    if [ $? -ne 0 ]; then
        echo "ERROR: Cannot get Grafana password"
        return 1
    fi
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s -f -u "$GRAFANA_USER:$password" "$GRAFANA_URL/api/health" >/dev/null 2>&1; then
            echo "Grafana is ready!"
            return 0
        fi

        echo "Attempt $attempt/$max_attempts: Grafana not ready yet, waiting..."
        sleep 10
        attempt=$((attempt + 1))
    done
   
    echo "ERROR: Grafana did not become ready within timeout"
    return 1
}

# Main refresh function
refresh_tokens() {
    echo "Starting token refresh at $(date)"
    
    # Get Grafana password
    local password
    password=$(get_grafana_password)
    if [ $? -ne 0 ]; then
        echo "ERROR: Cannot get Grafana password"
        return 1
    fi
    
    # Get fresh OAuth token
    local token
    token=$(get_oauth_token)
    
    if [ -z "$token" ] || [ "$token" = "null" ]; then
        echo "ERROR: Could not obtain OAuth token"
        return 1
    fi
    
    echo "Successfully obtained OAuth token"
    
    # Update datasources with the correct names
    update_datasource "gcp-prometheus-dev" "GCP Prometheus Dev" "lirvana-labs-development" "$token" true "$password"
    update_datasource "gcp-prometheus-prod" "GCP Prometheus Prod" "lirvana-labs-production" "$token" false "$password"
    
    echo "Token refresh completed at $(date)"
}

# Main execution
echo "Waiting for Grafana to be ready..."
wait_for_grafana

# Initial token refresh
refresh_tokens

# Periodic token refresh
while true; do
    sleep $REFRESH_INTERVAL
    refresh_tokens || echo "Token refresh failed, will retry in $REFRESH_INTERVAL seconds"
done
