#!/bin/bash

echo "========================================="
echo "💥 TESTING DLQ WITH SIMPLE FAILURE"
echo "========================================="

# Record current DLQ size
BEFORE_SIZE=$(curl -s http://localhost:9600/_node/stats | jq '.pipelines.main.dead_letter_queue.queue_size_in_bytes // 0')
echo "DLQ size before: $BEFORE_SIZE bytes"

# Backup current config
cp ./4-logstash/logstash.conf ./4-logstash/logstash.conf.backup

# Create a config that will definitely fail (invalid output)
cat > ./4-logstash/logstash.conf << 'FAIL'
input {
  kafka {
    bootstrap_servers => "kafka:9092"
    topics => ["logs"]
    group_id => "logstash-vl7"
    auto_offset_reset => "earliest"
    consumer_threads => 1
    codec => "plain"
  }
}

filter {
  # This will cause a parsing error
  json {
    source => "message"
    target => "parsed"
  }
}

output {
  # Invalid output that will cause connection failure
  http {
    url => "http://invalid-host-that-does-not-exist:9999/insert/jsonline"
    http_method => "post"
    format => "json"
  }
}
FAIL

echo "Created failing Logstash configuration"

# Create a test log
TEST_ID="DLQ_FAILURE_TEST_$(date +%s)"
docker exec log-generator sh -c "echo '{\"Body\":\"$TEST_ID\",\"Severity\":\"INFO\"}' >> /1-logs-storage/error-logs/dlq-test.log"
echo "Created test log: $TEST_ID"

# Restart Logstash
echo "Restarting Logstash with failing config..."
docker restart logstash

# Wait for processing
sleep 30

# Check DLQ size after
AFTER_SIZE=$(curl -s http://localhost:9600/_node/stats | jq '.pipelines.main.dead_letter_queue.queue_size_in_bytes // 0')
echo "DLQ size after: $AFTER_SIZE bytes"

# Check if test log is NOT in VictoriaLogs
echo -e "\nChecking if test log reached VictoriaLogs..."
RESULT=$(curl -s "http://localhost:9428/select/logsql/query?query=_msg:*$TEST_ID*")
if [ -z "$RESULT" ]; then
    echo "✅ Test log NOT in VictoriaLogs (expected - output failed)"
else
    echo "⚠️ Test log found in VictoriaLogs: $RESULT"
fi

# Restore original config
echo -e "\nRestoring original configuration..."
cp ./4-logstash/logstash.conf.backup ./4-logstash/logstash.conf
docker restart logstash

# Check DLQ again after restore
sleep 10
FINAL_SIZE=$(curl -s http://localhost:9600/_node/stats | jq '.pipelines.main.dead_letter_queue.queue_size_in_bytes // 0')
echo "DLQ size after restore: $FINAL_SIZE bytes"

if [ "$AFTER_SIZE" -gt "$BEFORE_SIZE" ]; then
    echo -e "\n✅ SUCCESS: DLQ captured failed events!"
    echo "Queue size increased from $BEFORE_SIZE to $AFTER_SIZE bytes"
    echo ""
    echo "To read DLQ contents, run: ./read-dlq.sh"
else
    echo -e "\n⚠️ DLQ did not capture events (may need more time)"
fi

echo ""
echo "========================================="