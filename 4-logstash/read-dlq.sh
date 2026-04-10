#!/bin/bash

echo "========================================="
echo "📖 READING DLQ CONTENTS"
echo "========================================="

# Check if DLQ has actual data
DLQ_SIZE=$(curl -s http://localhost:9600/_node/stats | jq '.pipelines.main.dead_letter_queue.queue_size_in_bytes // 0')

if [ "$DLQ_SIZE" -le 1 ]; then
    echo -e "\n⚠️ DLQ has no failed events (only metadata)"
    echo "Queue size: $DLQ_SIZE bytes"
    echo ""
    echo "To test DLQ with a real failure, run:"
    echo "  ./test-dlq-failure.sh"
    exit 0
fi

echo -e "\n📦 DLQ contains failed events. Reading...\n"

# Create DLQ reader config
cat > /tmp/dlq_reader.conf << 'CONF'
input {
  dead_letter_queue {
    path => "/usr/share/logstash/data/dlq"
    commit_offsets => false
    pipeline_id => "main"
  }
}
output {
  stdout { codec => rubydebug }
}
CONF

# Run Logstash DLQ reader
docker run --rm -it \
  -v $(pwd)/4-logstash/dlq:/usr/share/logstash/data/dlq:ro \
  -v /tmp/dlq_reader.conf:/tmp/dlq_reader.conf:ro \
  docker.elastic.co/logstash/logstash:9.3.2 \
  -f /tmp/dlq_reader.conf 2>/dev/null | head -100

echo ""
echo "========================================="