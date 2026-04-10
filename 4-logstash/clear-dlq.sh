#!/bin/bash

echo "========================================="
echo "🗑️  CLEARING DLQ"
echo "========================================="

# Check current size
CURRENT_SIZE=$(curl -s http://localhost:9600/_node/stats | jq '.pipelines.main.dead_letter_queue.queue_size_in_bytes // 0')
echo "Current DLQ size: $CURRENT_SIZE bytes"

if [ "$CURRENT_SIZE" -le 1 ]; then
    echo "DLQ is already clean"
    exit 0
fi

echo "Stopping Logstash..."
docker stop logstash

echo "Clearing DLQ files..."
rm -rf ./4-logstash/dlq/main/*
mkdir -p ./4-logstash/dlq/main

echo "Starting Logstash..."
docker start logstash

sleep 10

NEW_SIZE=$(curl -s http://localhost:9600/_node/stats | jq '.pipelines.main.dead_letter_queue.queue_size_in_bytes // 0')
echo "New DLQ size: $NEW_SIZE bytes"

if [ "$NEW_SIZE" -eq 1 ] || [ "$NEW_SIZE" -eq 0 ]; then
    echo "✅ DLQ cleared successfully"
else
    echo "⚠️ DLQ may not be fully cleared"
fi

echo "========================================="