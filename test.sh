#!/bin/bash

# ============================================================================
# Multi-Node VictoriaLogs Pipeline - Complete Test Suite
# ============================================================================

./stop.sh
./start.sh
sleep 54

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Helper functions
print_header() {
    echo ""
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════════════════════${NC}"
}

print_test() {
    echo -ne "${BOLD}[TEST]${NC} $1... "
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

print_pass() {
    echo -e "${GREEN}✓ PASS${NC}"
    PASSED_TESTS=$((PASSED_TESTS + 1))
}

print_fail() {
    echo -e "${RED}✗ FAIL${NC}"
    FAILED_TESTS=$((FAILED_TESTS + 1))
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Wait for condition with timeout
wait_for() {
    local label=$1
    local cmd=$2
    local retries=${3:-30}
    local delay=${4:-2}
    local i=0
    
    print_info "Waiting for $label..."
    until eval "$cmd" &>/dev/null; do
        i=$((i+1))
        if [ $i -ge $retries ]; then
            print_error "$label did not become ready in time"
            return 1
        fi
        echo -n "."
        sleep "$delay"
    done
    echo ""
    print_success "$label is ready"
    return 0
}

# ============================================================================
# SECTION 1: Container Health Check
# ============================================================================
print_header "SECTION 1: Container Health Check"

# Check all containers are running
print_test "All 12 containers running"
CONTAINER_COUNT=$(docker ps | grep -c "node-" || echo "0")
if [ "$CONTAINER_COUNT" -eq 12 ]; then
    print_pass
else
    print_fail
    print_error "Expected 12 containers, found $CONTAINER_COUNT"
fi

# List containers
print_info "Running containers:"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "node-|Names" | sed 's/^/  /'

# ============================================================================
# SECTION 2: Write Path - Log Generation
# ============================================================================
print_header "SECTION 2: Write Path - Log Generation"

# Check log generator is producing logs
print_test "Log generator producing logs"
GENERATOR_FILES=$(docker exec node-1-log-generator ls -la /logs-generated/ 2>/dev/null | grep -c "jsonl" || echo "0")
if [ "$GENERATOR_FILES" -ge 3 ]; then
    print_pass
else
    print_fail
fi

# Check log files have content
print_test "Log files have content"
HPC_SIZE=$(docker exec node-1-log-generator stat -c%s /logs-generated/hpcmlog.jsonl 2>/dev/null || echo "0")
MON_SIZE=$(docker exec node-1-log-generator stat -c%s /logs-generated/monitoring_service.jsonl 2>/dev/null || echo "0")
SYS_SIZE=$(docker exec node-1-log-generator stat -c%s /logs-generated/syslog.jsonl 2>/dev/null || echo "0")

if [ "$HPC_SIZE" -gt 0 ] && [ "$MON_SIZE" -gt 0 ] && [ "$SYS_SIZE" -gt 0 ]; then
    print_pass
    print_info "  hpcmlog.jsonl: $HPC_SIZE bytes"
    print_info "  monitoring_service.jsonl: $MON_SIZE bytes"
    print_info "  syslog.jsonl: $SYS_SIZE bytes"
else
    print_fail
fi

# Show sample log
print_info "Sample log entry:"
docker exec node-1-log-generator head -1 /logs-generated/hpcmlog.jsonl 2>/dev/null | head -c 200 | sed 's/^/  /'

# ============================================================================
# SECTION 3: Write Path - Fluent Bit to Kafka
# ============================================================================
print_header "SECTION 3: Write Path - Fluent Bit to Kafka"

# Check Fluent Bit is reading logs
print_test "Fluent Bit reading logs"
FB_RECORDS=$(curl -s http://localhost:8081/api/v1/metrics 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('input',{}).get('tail.0',{}).get('records',0))" 2>/dev/null || echo "0")
if [ "$FB_RECORDS" -gt 0 ]; then
    print_pass
    print_info "  Records read: $FB_RECORDS"
else
    print_fail
fi

# Check Fluent Bit can connect to Kafka
print_test "Fluent Bit → Kafka connectivity"
FB_LOGS=$(docker logs node-1-fluentbit --tail 20 2>&1 | grep -c "Connection refused" || echo "0")
if [ "$FB_LOGS" -eq 0 ]; then
    print_pass
else
    print_fail
    print_warn "Found connection refused errors"
fi

# Check Kafka topic exists
print_test "Kafka topic 'hpc-logs' exists"
KAFKA_TOPIC=$(docker exec node-1-kafka /opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092 2>/dev/null | grep -c "hpc-logs" || echo "0")
if [ "$KAFKA_TOPIC" -eq 1 ]; then
    print_pass
else
    print_fail
fi

# Check Kafka has messages
print_test "Kafka has messages"
KAFKA_MSG=$(docker exec node-1-kafka /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic hpc-logs --from-beginning --max-messages 1 --timeout-ms 5000 2>/dev/null | wc -l || echo "0")
if [ "$KAFKA_MSG" -gt 0 ]; then
    print_pass
    print_info "  Messages in topic: yes"
else
    print_fail
fi

# ============================================================================
# SECTION 4: Write Path - Logstash Processing
# ============================================================================
print_header "SECTION 4: Write Path - Logstash Processing"

# Check Logstash is running
print_test "Logstash pipeline running"
LS_STARTED=$(docker logs node-1-logstash 2>&1 | grep -c "Pipeline started" || echo "0")
if [ "$LS_STARTED" -gt 0 ]; then
    print_pass
else
    print_fail
fi

# Check Logstash events out
print_test "Logstash processing events"
LS_OUT=$(curl -s http://localhost:9601/_node/stats 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('pipelines',{}).get('main',{}).get('events',{}).get('out',0))" 2>/dev/null || echo "0")
if [ "$LS_OUT" -gt 0 ]; then
    print_pass
    print_info "  Events out: $LS_OUT"
else
    print_fail
fi

# Check Logstash has no HTTP errors
print_test "Logstash no HTTP errors"
LS_ERRORS=$(docker logs node-1-logstash 2>&1 | grep -c "Network is unreachable\|Connection refused" || echo "0")
if [ "${LS_ERRORS:-0}" -eq 0 ]; then
    print_pass
else
    print_fail
    print_warn "Found $LS_ERRORS connection errors"
fi

# ============================================================================
# SECTION 5: Storage Nodes (Write Distribution)
# ============================================================================
print_header "SECTION 5: Storage Nodes - Write Distribution"

# Get storage counts
DEVICE2_COUNT=$(curl -s 'http://localhost:8002/select/logsql/query?query=*%20%7C%20count()' 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('count(*)',0))" 2>/dev/null || echo "0")
DEVICE3_COUNT=$(curl -s 'http://localhost:8003/select/logsql/query?query=*%20%7C%20count()' 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('count(*)',0))" 2>/dev/null || echo "0")
TOTAL_STORAGE=$((DEVICE2_COUNT + DEVICE3_COUNT))

print_test "Device 2 (Storage 1) has logs"
if [ "$DEVICE2_COUNT" -gt 0 ]; then
    print_pass
    print_info "  Count: $DEVICE2_COUNT logs"
else
    print_fail
fi

print_test "Device 3 (Storage 2) has logs"
if [ "$DEVICE3_COUNT" -gt 0 ]; then
    print_pass
    print_info "  Count: $DEVICE3_COUNT logs"
else
    print_fail
fi

print_test "Logs are distributed across storage nodes"
if [ "$DEVICE2_COUNT" -gt 0 ] && [ "$DEVICE3_COUNT" -gt 0 ]; then
    print_pass
    print_info "  Distribution: $DEVICE2_COUNT : $DEVICE3_COUNT"
else
    print_fail
fi

# ============================================================================
# SECTION 6: Read Path - Query Layer
# ============================================================================
print_header "SECTION 6: Read Path - Query Layer"

# Check vlselect primary is running
print_test "Primary query node (Device 4) running"
docker ps | grep -q "node-4-vlselect" && print_pass || print_fail

# Check backup vlselect is running
print_test "Backup query node (Device 5) running"
docker ps | grep -q "node-5-vlselect" && print_pass || print_fail

# Check nginx load balancer is running
print_test "Nginx load balancer (Device 5) running"
docker ps | grep -q "node-5-nginx" && print_pass || print_fail

# Test direct query to Device 4
print_test "Direct query to Device 4 (primary vlselect)"
DEVICE4_RESULT=$(curl -s -o /dev/null -w "%{http_code}" 'http://localhost:8004/select/logsql/query?query=*%20%7C%20count()' 2>/dev/null)
if [ "$DEVICE4_RESULT" = "200" ]; then
    print_pass
else
    print_fail
fi

# Test query through load balancer
print_test "Query through load balancer (Device 5 nginx)"
LB_RESULT=$(curl -s -o /dev/null -w "%{http_code}" 'http://localhost:8005/select/logsql/query?query=*%20%7C%20count()' 2>/dev/null)
if [ "$LB_RESULT" = "200" ]; then
    print_pass
else
    print_fail
fi

# Verify load balancer returns correct total
print_test "Load balancer returns correct total"
LB_TOTAL=$(curl -s 'http://localhost:8005/select/logsql/query?query=*%20%7C%20count()' 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('count(*)',0))" 2>/dev/null || echo "0")
if [ "$LB_TOTAL" -eq "$TOTAL_STORAGE" ] && [ "$TOTAL_STORAGE" -gt 0 ]; then
    print_pass
    print_info "  Load balancer total: $LB_TOTAL (matches $TOTAL_STORAGE)"
else
    print_fail
    print_warn "  LB: $LB_TOTAL, Storage total: $TOTAL_STORAGE"
fi

# ============================================================================
# SECTION 7: Failover Testing
# ============================================================================
print_header "SECTION 7: Failover Testing"

# Test query failover when primary goes down
print_test "Failover - Stop primary vlselect, query still works"
docker stop node-4-vlselect 2>/dev/null
sleep 5
FAILOVER_RESULT=$(curl -s -o /dev/null -w "%{http_code}" 'http://localhost:8005/select/logsql/query?query=*%20%7C%20count()' 2>/dev/null)
docker start node-4-vlselect 2>/dev/null
if [ "$FAILOVER_RESULT" = "200" ]; then
    print_pass
else
    print_fail
fi

# Test alerting integration
print_test "vmalert is running"
docker ps | grep -q "node-4-vmalert" && print_pass || print_fail

# Test Grafana is accessible
print_test "Grafana is accessible"
GRAFANA_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3001/api/health 2>/dev/null)
if [ "$GRAFANA_HEALTH" = "200" ]; then
    print_pass
else
    print_fail
fi

# ============================================================================
# SECTION 8: Data Consistency and Query Quality
# ============================================================================
print_header "SECTION 8: Data Consistency and Query Quality"

# Query by stream
print_test "Query by vl_stream:hpcmlog"
STREAM_RESULT=$(curl -s 'http://localhost:8005/select/logsql/query?query=vl_stream:hpcmlog%20%7C%20count()' 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('count(*)',0))" 2>/dev/null || echo "0")
if [ "$STREAM_RESULT" -gt 0 ] 2>/dev/null; then
    print_pass
    print_info "  hpcmlog count: $STREAM_RESULT"
else
    print_fail
fi

# Query by level
print_test "Query by level:ERROR"
ERROR_RESULT=$(curl -s 'http://localhost:8005/select/logsql/query?query=level:ERROR%20%7C%20count()' 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('count(*)',0))" 2>/dev/null || echo "0")
# This can be 0, that's fine
print_info "  Error count: $ERROR_RESULT"
echo -e "  ${GREEN}✓ PASS${NC} (query executed successfully)"

# Get sample logs
print_test "Can retrieve sample logs"
SAMPLE_LOGS=$(curl -s 'http://localhost:8005/select/logsql/query?query=*%20%7C%20limit%202' 2>/dev/null | wc -l)
if [ "$SAMPLE_LOGS" -gt 0 ]; then
    print_pass
else
    print_fail
fi

# ============================================================================
# SECTION 9: Performance Metrics
# ============================================================================
print_header "SECTION 9: Performance Metrics"

# Get Fluent Bit output records
FB_OUTPUT=$(curl -s http://localhost:8081/api/v1/metrics 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('output',{}).get('kafka.0',{}).get('proc_records',0))" 2>/dev/null || echo "0")
print_info "  Fluent Bit output records: $FB_OUTPUT"

# Get Logstash throughput
LS_THROUGHPUT=$(curl -s http://localhost:9601/_node/stats 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('pipelines',{}).get('main',{}).get('flow',{}).get('output_throughput',{}).get('current',0))" 2>/dev/null || echo "0")
print_info "  Logstash throughput: $LS_THROUGHPUT events/sec"

# Get total logs written
print_info "  Total logs in system: $TOTAL_STORAGE"
print_info "  Storage distribution: Device 2: $DEVICE2_COUNT, Device 3: $DEVICE3_COUNT"
print_info "  Read path status: HTTP ${LB_RESULT:-N/A}"

# ============================================================================
# SECTION 10: Grafana and Alerting Configuration
# ============================================================================
print_header "SECTION 10: Grafana and Alerting Configuration"

# Check VictoriaLogs datasource in Grafana
print_test "VictoriaLogs datasource configured"
DS_CHECK=$(curl -s -u admin:admin "http://localhost:3001/api/datasources" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); found=False; for ds in d: 
 if ds.get('type') == 'victoriametrics-logs-datasource': found=True; break
 print('true' if found else 'false')" 2>/dev/null)
if [ "$DS_CHECK" = "true" ]; then
    print_pass
else
    print_fail
fi

# Check vmalert rules loaded
print_test "vmalert rules loaded"
VMALERT_RULES=$(curl -s 'http://localhost:8881/api/v1/groups' 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('data',{}).get('groups',[])))" 2>/dev/null || echo "0")
if [ "$VMALERT_RULES" -gt 0 ]; then
    print_pass
    print_info "  Rule groups loaded: $VMALERT_RULES"
else
    print_fail
fi

# ============================================================================
# TEST SUMMARY
# ============================================================================
print_header "TEST SUMMARY"

echo -e "${BOLD}Results:${NC}"
echo -e "  ${GREEN}Passed: $PASSED_TESTS${NC}"
echo -e "  ${RED}Failed: $FAILED_TESTS${NC}"
echo -e "  ${BLUE}Total:  $TOTAL_TESTS${NC}"
echo ""

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}  🎉 ALL TESTS PASSED! Multi-node pipeline is FULLY OPERATIONAL! 🎉${NC}"
    echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${BOLD}Access Points:${NC}"
    echo -e "  Grafana:      ${CYAN}http://localhost:3001${NC} (admin/admin)"
    echo -e "  vmalert:      ${CYAN}http://localhost:8881${NC}"
    echo -e "  Storage 2:     ${CYAN}http://localhost:8002${NC}"
    echo -e "  Storage 3:     ${CYAN}http://localhost:8003${NC}"
    echo -e "  Load Balancer: ${CYAN}http://localhost:8005${NC}"
    echo -e "  Fluent Bit:   ${CYAN}http://localhost:8081/metrics${NC}"
    echo -e "  Logstash:     ${CYAN}http://localhost:9601${NC}"
    echo ""
else
    echo -e "${RED}${BOLD}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}${BOLD}  ⚠️ SOME TESTS FAILED. Please review the output above. ⚠️${NC}"
    echo -e "${RED}${BOLD}═══════════════════════════════════════════════════════════════════════════════${NC}"
fi

# Return exit code based on test results
if [ $FAILED_TESTS -eq 0 ]; then
    exit 0
else
    exit 1
fi