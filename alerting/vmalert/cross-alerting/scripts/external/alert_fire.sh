#!/bin/bash

ALERTMANAGER_URL="http://localhost:9093/api/v2/alerts"

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
ENDS=$(date -u -d "+5 minutes" +"%Y-%m-%dT%H:%M:%SZ")

curl -X POST "$ALERTMANAGER_URL" \
  -H "Content-Type: application/json" \
  -d "[
    {
      \"labels\": {
        \"alertname\": \"NodeHeartbeat\",
        \"node\": \"node-a\",
        \"severity\": \"critical\"
      },
      \"annotations\": {
        \"summary\": \"Heartbeat missing\",
        \"description\": \"Node A heartbeat NOT detected\"
      },
      \"startsAt\": \"$NOW\",
      \"endsAt\": \"$ENDS\"
    }
  ]"