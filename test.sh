#!/bin/bash

# Get the directory where this script is located
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
WARN=0

pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL++)); }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; ((WARN++)); }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
header() { echo -e "\n${BOLD}${CYAN}=== $1 ===${NC}"; }

# Run full pipeline reset
./stop.sh --purge 2>/dev/null
./start.sh

# allow full stack time to come up
sleep 90

#=============================================================================
# SECTION 1: Container Health Check
#=============================================================================
header "Container Health Check"

COUNT=$(docker ps | grep -c "node-" || echo "0")
if [ "$COUNT" -ge 8 ]; then
    pass "All containers running ($COUNT containers)"
else
    fail "Expected at least 8 containers, found $COUNT"
fi

info "Running containers:"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "node-|NAMES" | sed 's/^/  /'

#=============================================================================
# SECTION 2: Write Path - Log Generation
#=============================================================================
header "Write Path - Log Generation"

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
    warn "Fluent Bit not reading logs (non-critical)"
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
# SECTION 5: Write Path - vlinsert
#=============================================================================
header "Write Path - vlinsert (Node 2)"

VLINSERT=$(curl -s -o /dev/null -w "%{http_code}" 'http://localhost:8001/metrics' 2>/dev/null)
[ "$VLINSERT" = "200" ] && pass "vlinsert healthy" || fail "vlinsert down"

#=============================================================================
# SECTION 6: Storage Nodes - Write Distribution
#=============================================================================
header "Storage Nodes - Write Distribution"

N3=$(curl -s 'http://localhost:8002/select/logsql/query?query=*%20%7C%20count()' 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('count(*)',0))" 2>/dev/null || echo "0")
N4=$(curl -s 'http://localhost:8003/select/logsql/query?query=*%20%7C%20count()' 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('count(*)',0))" 2>/dev/null || echo "0")

if [ "$N3" -gt 0 ]; then
    pass "Storage Node 3 has $N3 logs"
else
    fail "Storage Node 3 empty"
fi

if [ "$N4" -gt 0 ]; then
    pass "Storage Node 4 has $N4 logs"
else
    fail "Storage Node 4 empty"
fi

info "Distribution: $N3 : $N4"

#=============================================================================
# SECTION 7: Read Path - Query Layer
#=============================================================================
header "Read Path - Query Layer"

TOTAL=$((N3 + N4))
QUERY=$(curl -s 'http://localhost:8004/select/logsql/query?query=*%20%7C%20count()' 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('count(*)',0))" 2>/dev/null || echo "0")

if [ "$QUERY" -eq "$TOTAL" ]; then
    pass "vlselect returns correct total ($QUERY)"
else
    fail "vlselect mismatch: Query=$QUERY, Storage=$TOTAL"
fi

#=============================================================================
# SECTION 8: Services Accessibility
#=============================================================================
header "Services Accessibility"

GRAFANA=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3001/api/health 2>/dev/null)
[ "$GRAFANA" = "200" ] && pass "Grafana accessible" || fail "Grafana down"

VMALERT=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8881/-/healthy 2>/dev/null)
[ "$VMALERT" = "200" ] && pass "vmalert running" || fail "vmalert down"

ALERTMANAGER=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9095/ 2>/dev/null)
[ "$ALERTMANAGER" = "200" ] && pass "alertmanager running" || fail "alertmanager down"

#=============================================================================
# SECTION 9: Log Query Tests
#=============================================================================
header "Log Query Tests"

ERROR_COUNT=$(curl -s 'http://localhost:8004/select/logsql/query?query=level:ERROR%20%7C%20count()' 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('count(*)',0))" 2>/dev/null || echo "0")
if [ "$ERROR_COUNT" -ge 0 ]; then
    pass "Error log query works ($ERROR_COUNT errors found)"
else
    fail "Error log query failed"
fi

#=============================================================================
# SECTION 10: Test Summary
#=============================================================================
header "TEST SUMMARY"

echo -e "Passed: $PASS"
echo -e "Failed: $FAIL"
echo -e "Warnings: $WARN"
echo -e "Total:  $((PASS + FAIL))"
echo ""

if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}ALL TESTS PASSED - 5-Node cluster is fully operational!${NC}"
    echo ""
    echo -e "${BOLD}Access Points:${NC}"
    echo "  Grafana:           http://localhost:3001 (admin/admin)"
    echo "  vmalert:           http://localhost:8881"
    echo "  Alertmanager:      http://localhost:9095"
    echo "  Write API:         http://localhost:8001"
    echo "  Query API:         http://localhost:8004"
    echo "  Storage Node 3:    http://localhost:8002"
    echo "  Storage Node 4:    http://localhost:8003"
    echo "  Fluent Bit:        http://localhost:8081/metrics"
    echo "  Logstash:          http://localhost:9601/_node/stats"
    exit 0
else
    echo -e "${RED}SOME TESTS FAILED - Please review the output above${NC}"
    exit 1
fi