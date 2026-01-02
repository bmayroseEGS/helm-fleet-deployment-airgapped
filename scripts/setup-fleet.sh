#!/bin/bash
################################################################################
# Fleet Setup Script via Kibana API
# Purpose: Configure Fleet to allow HTTP Fleet Server (bypass HTTPS requirement)
################################################################################

set -e

# Configuration
KIBANA_URL="${KIBANA_URL:-http://localhost:5601}"
KIBANA_USER="${KIBANA_USER:-elastic}"
KIBANA_PASSWORD="${KIBANA_PASSWORD:-elastic}"
FLEET_SERVER_URL="${FLEET_SERVER_URL:-http://fleet-server:8220}"
ELASTICSEARCH_URL="${ELASTICSEARCH_URL:-http://elasticsearch-master:9200}"

echo "========================================="
echo "Fleet Setup via Kibana API"
echo "========================================="
echo ""
echo "Kibana URL: $KIBANA_URL"
echo "Fleet Server URL: $FLEET_SERVER_URL"
echo "Elasticsearch URL: $ELASTICSEARCH_URL"
echo ""

# Wait for Kibana to be ready
echo "Waiting for Kibana to be ready..."
until curl -sf -u "$KIBANA_USER:$KIBANA_PASSWORD" "$KIBANA_URL/api/status" >/dev/null 2>&1; do
  echo "  Waiting for Kibana..."
  sleep 5
done
echo "✓ Kibana is ready"
echo ""

# Setup Fleet
echo "Setting up Fleet..."

# Create Fleet Server host
echo "1. Creating Fleet Server host..."
FLEET_HOST_RESPONSE=$(curl -s -X POST "$KIBANA_URL/api/fleet/fleet_server_hosts" \
  -u "$KIBANA_USER:$KIBANA_PASSWORD" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"Fleet Server\",
    \"host_urls\": [\"$FLEET_SERVER_URL\"],
    \"is_default\": true
  }")

if echo "$FLEET_HOST_RESPONSE" | grep -q "id"; then
  FLEET_HOST_ID=$(echo "$FLEET_HOST_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
  echo "✓ Fleet Server host created with ID: $FLEET_HOST_ID"
else
  echo "Response: $FLEET_HOST_RESPONSE"
  if echo "$FLEET_HOST_RESPONSE" | grep -q "already exists"; then
    echo "✓ Fleet Server host already exists"
  else
    echo "✗ Failed to create Fleet Server host"
  fi
fi
echo ""

# Update or create default Elasticsearch output
echo "2. Configuring Elasticsearch output..."
OUTPUT_RESPONSE=$(curl -s -X POST "$KIBANA_URL/api/fleet/outputs" \
  -u "$KIBANA_USER:$KIBANA_PASSWORD" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"default\",
    \"type\": \"elasticsearch\",
    \"hosts\": [\"$ELASTICSEARCH_URL\"],
    \"is_default\": true,
    \"is_default_monitoring\": true,
    \"config_yaml\": \"ssl.verification_mode: none\"
  }")

if echo "$OUTPUT_RESPONSE" | grep -q "id"; then
  OUTPUT_ID=$(echo "$OUTPUT_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
  echo "✓ Elasticsearch output created with ID: $OUTPUT_ID"
else
  echo "Response: $OUTPUT_RESPONSE"
  if echo "$OUTPUT_RESPONSE" | grep -q "already exists"; then
    echo "✓ Elasticsearch output already exists"
  else
    echo "⚠ Could not create output, may already exist"
  fi
fi
echo ""

# Create Fleet Server policy
echo "3. Creating Fleet Server policy..."
POLICY_RESPONSE=$(curl -s -X POST "$KIBANA_URL/api/fleet/agent_policies" \
  -u "$KIBANA_USER:$KIBANA_PASSWORD" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "fleet-server-policy",
    "namespace": "default",
    "description": "Fleet Server policy for air-gapped deployment",
    "monitoring_enabled": ["logs", "metrics"],
    "has_fleet_server": true
  }')

if echo "$POLICY_RESPONSE" | grep -q "id"; then
  POLICY_ID=$(echo "$POLICY_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
  echo "✓ Fleet Server policy created with ID: $POLICY_ID"
else
  echo "Response: $POLICY_RESPONSE"
  if echo "$POLICY_RESPONSE" | grep -q "already exists\|fleet-server-policy"; then
    echo "✓ Fleet Server policy already exists"
  else
    echo "⚠ Could not create policy, may already exist"
  fi
fi
echo ""

# Get Fleet setup status
echo "4. Checking Fleet setup status..."
SETUP_RESPONSE=$(curl -s -X GET "$KIBANA_URL/api/fleet/setup" \
  -u "$KIBANA_USER:$KIBANA_PASSWORD" \
  -H "kbn-xsrf: true")

echo "Fleet setup status:"
echo "$SETUP_RESPONSE" | grep -o '"isReady":[^,]*' || echo "  Status: $(echo $SETUP_RESPONSE | head -c 200)"
echo ""

echo "========================================="
echo "Fleet Setup Complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo "  1. Deploy Fleet Server:"
echo "     helm install fleet-server ./helm_charts/fleet-server --namespace elastic"
echo ""
echo "  2. Monitor Fleet Server startup:"
echo "     kubectl logs -n elastic -l app=fleet-server -f"
echo ""
echo "  3. Verify in Kibana UI:"
echo "     Management → Fleet → Fleet Servers"
echo ""
