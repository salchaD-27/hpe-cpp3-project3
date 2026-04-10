#!/bin/bash
echo "=== DLQ Statistics ==="
curl -s http://localhost:9600/_node/stats | jq '{
  queue_size_bytes: .pipelines.main.dead_letter_queue.queue_size_in_bytes,
  max_size_bytes: .pipelines.main.dead_letter_queue.max_queue_size_in_bytes,
  dropped_events: .pipelines.main.dead_letter_queue.dropped_events,
  expired_events: .pipelines.main.dead_letter_queue.expired_events,
  storage_policy: .pipelines.main.dead_letter_queue.storage_policy
}'

echo -e "\n=== DLQ Directory Contents ==="
docker exec logstash du -sh /usr/share/logstash/data/dlq/
docker exec logstash ls -laR /usr/share/logstash/data/dlq/ | head -20

echo -e "\n=== Recent Failures in Logs ==="
docker logs logstash --tail 50 | grep -i "error\|fail\|exception" | tail -10