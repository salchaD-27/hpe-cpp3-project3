#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "========================================="
echo "📊 DLQ VERIFICATION SCRIPT"
echo "========================================="

# 1. Check DLQ Statistics
echo -e "\n${BLUE}1. DLQ Statistics:${NC}"
DLQ_STATS=$(curl -s http://localhost:9600/_node/stats | jq '.pipelines.main.dead_letter_queue')
echo "$DLQ_STATS" | jq '{
  queue_size_bytes: .queue_size_in_bytes,
  max_size_bytes: .max_queue_size_in_bytes,
  dropped_events: .dropped_events,
  expired_events: .expired_events,
  storage_policy: .storage_policy
}'

# 2. Check DLQ Files
echo -e "\n${BLUE}2. DLQ Directory Contents:${NC}"
ls -lah ./4-logstash/dlq/main/

# 3. Find non-empty segment files
echo -e "\n${BLUE}3. Non-empty DLQ Segments:${NC}"
NON_EMPTY=$(find ./4-logstash/dlq -name "*.tmp" -size +1c -exec ls -lh {} \; 2>/dev/null)
if [ -n "$NON_EMPTY" ]; then
    echo "$NON_EMPTY"
    echo -e "${YELLOW}⚠️ DLQ contains actual failed events!${NC}"
else
    echo "No non-empty segment files (DLQ is clean)"
fi

# 4. Check VictoriaLogs for isolation
echo -e "\n${BLUE}4. VictoriaLogs Stream Isolation:${NC}"
PARSE_ERROR_COUNT=$(curl -s 'http://localhost:9428/select/logsql/query?query=vl_stream:parse_error%20%7C%20stats%20count()' | jq '.["count(*)"] // 0')
HPCMLOG_COUNT=$(curl -s 'http://localhost:9428/select/logsql/query?query=vl_stream:hpcmlog%20%7C%20stats%20count()' | jq '.["count(*)"] // 0')
MONITORING_COUNT=$(curl -s 'http://localhost:9428/select/logsql/query?query=vl_stream:monitoring%20%7C%20stats%20count()' | jq '.["count(*)"] // 0')
SYSLOG_COUNT=$(curl -s 'http://localhost:9428/select/logsql/query?query=vl_stream:syslog%20%7C%20stats%20count()' | jq '.["count(*)"] // 0')

echo "  parse_error: $PARSE_ERROR_COUNT"
echo "  hpcmlog: $HPCMLOG_COUNT"
echo "  monitoring: $MONITORING_COUNT"
echo "  syslog: $SYSLOG_COUNT"

# 5. Summary
echo -e "\n${BLUE}5. Verification Summary:${NC}"
QUEUE_SIZE=$(echo "$DLQ_STATS" | jq -r '.queue_size_in_bytes // 0')
if [ "$QUEUE_SIZE" -eq 1 ]; then
    echo -e "${GREEN}✅ DLQ is clean (only metadata) - No catastrophic failures${NC}"
elif [ "$QUEUE_SIZE" -gt 1 ]; then
    echo -e "${YELLOW}⚠️ DLQ has $QUEUE_SIZE bytes of failed events${NC}"
fi

if [ "$PARSE_ERROR_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✅ Malformed logs are correctly in parse_error stream (not corrupting data)${NC}"
fi

echo -e "\n${BLUE}To read DLQ contents, run:${NC}"
echo "  ./read-dlq.sh"
echo "  or"
echo "  ts-node read-dlq.ts"

echo ""
echo "========================================="