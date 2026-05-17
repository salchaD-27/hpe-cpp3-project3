#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS=0
FAIL=0

pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL++)); }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
header() { echo -e "\n${BOLD}${CYAN}=== $1 ===${NC}"; }

# Run full pipeline reset
./stop.sh --purge 2>/dev/null
./start.sh
sleep 54

#=============================================================================
# SECTION 1: Container Health Check
#=============================================================================
header "Container Health Check"

COUNT=$(docker ps | grep -c "node-" || echo "0")
if [ "$COUNT" -eq 12 ]; then
    pass "All 12 containers running"
else
    fail "Expected 12 containers, found $COUNT"
fi

info "Running containers:"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "node-|NAMES" | sed 's/^/  /'

#=============================================================================
# SECTION 2: Write Path - Log Generation
#=============================================================================
header "Write Path - Log Generation"

# Check log files exist
HPC_SIZE=$(docker exec node-1-log-generator stat -c%s /logs-generated/hpcmlog.jsonl 2>/dev/null || echo "0")
MON_SIZE=$(docker exec node-1-log-generator stat -c%s /logs-generated/monitoring_service.jsonl 2>/dev/null || echo "0")
SYS_SIZE=$(docker exec node-1-log-generator stat -c%s /logs-generated/syslog.jsonl 2>/dev/null || echo "0")

if [ "$HPC_SIZE" -gt 0 ] && [ "$MON_SIZE" -gt 0 ] && [ "$SYS_SIZE" -gt 0 ]; then
    pass "Log files have content"
    info "  hpcmlog.jsonl: $HPC_SIZE bytes"
    info "  monitoring_service.jsonl: $MON_SIZE bytes"
    info "  syslog.jsonl: $SYS_SIZE bytes"
else
    fail "Log files empty"
fi

#=============================================================================
# SECTION 3: Write Path - Fluent Bit to Kafka
#=============================================================================
header "Write Path - Fluent Bit to Kafka"

FB_RECORDS=$(curl -s http://localhost:8081/api/v1/metrics 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('input',{}).get('tail.0',{}).get('records',0))" 2>/dev/null || echo "0")
if [ "$FB_RECORDS" -gt 0 ]; then
    pass "Fluent Bit reading logs ($FB_RECORDS records)"
else
    fail "Fluent Bit not reading logs"
fi

KAFKA_MSG=$(docker exec node-1-kafka /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic hpc-logs --from-beginning --max-messages 1 --timeout-ms 5000 2>/dev/null | wc -l)
if [ "$KAFKA_MSG" -gt 0 ]; then
    pass "Kafka has messages"
else
    fail "Kafka empty"
fi

#=============================================================================
# SECTION 4: Write Path - Logstash Processing
#=============================================================================
header "Write Path - Logstash Processing"

LS_OUT=$(curl -s http://localhost:9601/_node/stats 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('pipelines',{}).get('main',{}).get('events',{}).get('out',0))" 2>/dev/null || echo "0")
if [ "$LS_OUT" -gt 0 ]; then
    pass "Logstash processing ($LS_OUT events)"
else
    fail "Logstash not processing"
fi

#=============================================================================
# SECTION 5: Storage Nodes - Write Distribution
#=============================================================================
header "Storage Nodes - Write Distribution"

N2=$(curl -s 'http://localhost:8002/select/logsql/query?query=*%20%7C%20count()' 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('count(*)',0))" 2>/dev/null || echo "0")
N3=$(curl -s 'http://localhost:8003/select/logsql/query?query=*%20%7C%20count()' 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('count(*)',0))" 2>/dev/null || echo "0")

if [ "$N2" -gt 0 ]; then
    pass "Storage Node 1 has $N2 logs"
else
    fail "Storage Node 1 empty"
fi

if [ "$N3" -gt 0 ]; then
    pass "Storage Node 2 has $N3 logs"
else
    fail "Storage Node 2 empty"
fi

info "Distribution: $N2 : $N3"

#=============================================================================
# SECTION 6: Read Path - Query Layer
#=============================================================================
header "Read Path - Query Layer"

LB=$(curl -s 'http://localhost:8005/select/logsql/query?query=*%20%7C%20count()' 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('count(*)',0))" 2>/dev/null || echo "0")
if [ "$LB" -eq $((N2 + N3)) ]; then
    pass "Load balancer returns correct total ($LB)"
else
    fail "Load balancer mismatch: LB=$LB, Storage=$((N2 + N3))"
fi

# Test direct query
DIRECT=$(curl -s -o /dev/null -w "%{http_code}" 'http://localhost:8004/select/logsql/query?query=*%20%7C%20count()' 2>/dev/null)
[ "$DIRECT" = "200" ] && pass "Direct query to Node 4 works" || fail "Direct query to Node 4 failed"

#=============================================================================
# SECTION 7: Failover Testing
#=============================================================================
header "Failover Testing"

docker stop node-4-vlselect 2>/dev/null
sleep 5
FAILOVER=$(curl -s -o /dev/null -w "%{http_code}" 'http://localhost:8005/select/logsql/query?query=*%20%7C%20count()' 2>/dev/null)
docker start node-4-vlselect 2>/dev/null

if [ "$FAILOVER" = "200" ]; then
    pass "Failover works (backup vlselect took over)"
else
    fail "Failover failed (HTTP $FAILOVER)"
fi

#=============================================================================
#=============================================================================
# SECTION 8: Services Accessibility (incl alerting)
#=============================================================================
#=============================================================================
header "Services Accessibility"

GRAFANA=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3001/api/health 2>/dev/null)
[ "$GRAFANA" = "200" ] && pass "Grafana accessible" || fail "Grafana down"

VMALERT=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8881/-/healthy 2>/dev/null)
[ "$VMALERT" = "200" ] && pass "vmalert running" || fail "vmalert down"

ALERTMANAGER=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9095/ 2>/dev/null)
[ "$ALERTMANAGER" = "200" ] && pass "alertmanager running" || fail "alertmanager down"


#=============================================================================
# SECTION 9: Test Summary
#=============================================================================
header "TEST SUMMARY"

echo -e "Passed: $PASS"
echo -e "Failed: $FAIL"
echo -e "Total:  $((PASS + FAIL))"
echo ""

if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}ALL TESTS PASSED - Multi-node pipeline is fully operational!${NC}"
    echo ""
    echo -e "${BOLD}Access Points:${NC}"
    echo "  Grafana:      http://localhost:3001 (admin/admin)"
    echo "  vmalert:      http://localhost:8881"
    echo "  Load Balancer: http://localhost:8005"
    echo "  Storage 1:    http://localhost:8002"
    echo "  Storage 2:    http://localhost:8003"
    echo "  Fluent Bit:   http://localhost:8081/metrics"
    echo "  Logstash:     http://localhost:9601/_node/stats"
    exit 0
else
    echo -e "${RED}SOME TESTS FAILED - Please review the output above${NC}"
    exit 1
fi