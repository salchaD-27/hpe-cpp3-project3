#!/bin/bash

ALERTMANAGER_URL="http://localhost:9093/api/v2/alerts"

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

curl -X POST "$ALERTMANAGER_URL" \
  -H "Content-Type: application/json" \
  -d "[
    {
      \"labels\": {
        \"alertgroup\": \"heartbeat-demo\",
        \"alertname\": \"NodeHeartbeatDetected\",
        \"stats_result\": \"heartbeats\",
        \"severity\": \"critical\"
      },
      \"annotations\": {
        \"summary\": \"Heartbeat restored\",
        \"description\": \"Node A heartbeat detected\"
      }
    }
  ]"