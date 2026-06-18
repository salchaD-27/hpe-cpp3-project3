#!/bin/bash

NODE_NAME="node-a"
LOG_DIR="generated-logs"
LOG_FILE="$LOG_DIR/heartbeat.jsonl"

mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

while true; do
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  echo "{\"Resource\":{\"service.name\":\"heartbeat_detected\"},\"Body\":\"$NODE_NAME heartbeat detected\",\"Attributes\":{\"monitoring_services.filename\":\"$LOG_FILE\",\"node\":\"$NODE_NAME\",\"timestamp\":\"$timestamp\",\"event.type\":\"heartbeat\"},\"Severity\":\"INFO\"}" >> "$LOG_FILE"

  sleep 1
done