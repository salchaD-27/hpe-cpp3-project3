#!/bin/bash

echo "========================================="
echo "🧪 TESTING DLQ WITH FAILURE"
echo "========================================="

# Record current DLQ size
BEFORE_SIZE=$(curl -s http://localhost:9600/_node/stats | jq '.pipelines.main.dead_letter_queue.queue_size_in_bytes // 0')
echo "DLQ size before: $BEFORE_SIZE bytes"

# Create a truly unprocessable log (binary data)
echo -e "\nCreating malformed log that will fail..."
docker exec log-generator sh -c "printf '\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A\x0B\x0C\x0D\x0E\x0F' >> /1-logs-storage/error-logs/binary-failure.log"

# Create another clearly invalid log
docker exec log-generator sh -c "echo 'COMPLETELY_INVALID_UNPARSABLE_CONTENT_$(date +%s)' >> /1-logs-storage/error-logs/text-failure.log"

echo "Created test failure logs"

# Wait for processing
echo "Waiting 30 seconds for processing..."
sleep 30

# Check DLQ size after
AFTER_SIZE=$(curl -s http://localhost:9600/_node/stats | jq '.pipelines.main.dead_letter_queue.queue_size_in_bytes // 0')
echo "DLQ size after: $AFTER_SIZE bytes"

if [ "$AFTER_SIZE" -gt "$BEFORE_SIZE" ]; then
    echo -e "\n✅ SUCCESS: DLQ captured failed events!"
    echo "Queue size increased from $BEFORE_SIZE to $AFTER_SIZE bytes"
else
    echo -e "\n⚠️ DLQ size didn't increase. Check Logstash logs:"
    docker logs logstash --tail 20 | grep -i error
fi

# Verify logs did NOT go to VictoriaLogs
echo -e "\nVerifying failed logs are NOT in VictoriaLogs..."
RESULT=$(curl -s 'http://localhost:9428/select/logsql/query?query=_msg:*COMPLETELY_INVALID_UNPARSABLE_CONTENT*')
if [ -z "$RESULT" ] || [ "$RESULT" = "null" ]; then
    echo "✅ Failed logs correctly NOT in VictoriaLogs"
else
    echo "❌ BUG: Failed logs found in VictoriaLogs"
fi

echo ""
echo "========================================="
