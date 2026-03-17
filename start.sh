#!/bin/bash

set -euo pipefail

###############################################################################
# COLORS
###############################################################################
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

###############################################################################
# HELPERS
###############################################################################
log()     { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $*"; }
success() { echo -e "${GREEN}[$(date '+%H:%M:%S')] ✓ $*${NC}"; }
warn()    { echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠ $*${NC}"; }
error()   { echo -e "${RED}[$(date '+%H:%M:%S')] ✗ $*${NC}"; }
section() { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${NC}"; \
            echo -e "${BOLD}${CYAN}  $*${NC}"; \
            echo -e "${BOLD}${CYAN}══════════════════════════════════════════${NC}\n"; }

wait_for() {
  local label=$1
  local cmd=$2
  local retries=${3:-30}
  local delay=${4:-3}
  local i=0
  log "Waiting for $label..."
  until eval "$cmd" &>/dev/null; do
    i=$((i+1))
    if [ $i -ge $retries ]; then
      error "$label did not become ready in time"
      return 1
    fi
    echo -n "."
    sleep "$delay"
  done
  echo ""
  success "$label is ready"
}

###############################################################################
# PREFLIGHT
###############################################################################
section "PREFLIGHT CHECKS"

for cmd in docker curl; do
  if command -v $cmd &>/dev/null; then
    success "$cmd found"
  else
    error "$cmd not found — please install it"
    exit 1
  fi
done

if ! docker info &>/dev/null; then
  error "Docker daemon is not running"
  exit 1
fi
success "Docker daemon running"

###############################################################################
# CLEAN START
###############################################################################
section "CLEAN START"

log "Stopping and removing existing containers and volumes..."
docker compose down -v --remove-orphans 2>&1 | grep -E "Removed|Stopped|Network|Volume" || true

log "Clearing old log file..."
rm -f ./0-logs/hpc-cluster.log
mkdir -p ./0-logs
success "Clean slate ready"

###############################################################################
# BUILD
###############################################################################
section "BUILDING IMAGES"

log "Building log generator image..."
docker compose build generator 2>&1 | grep -E "Step|Successfully|ERROR|error" || true
success "Build complete"

###############################################################################
# START CORE SERVICES
###############################################################################
section "STARTING CORE SERVICES"

log "Starting Kafka and VictoriaLogs..."
docker compose up -d kafka victorialogs
success "Kafka and VictoriaLogs started"

###############################################################################
# WAIT FOR KAFKA
###############################################################################
section "WAITING FOR KAFKA"

wait_for "Kafka broker" \
  "docker exec kafka /opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092" \
  30 3

# verify topic auto-creation works
log "Verifying Kafka topic 'logs'..."
sleep 3
docker exec kafka /opt/kafka/bin/kafka-topics.sh \
  --list --bootstrap-server localhost:9092 2>/dev/null | grep -q "logs" \
  && success "Topic 'logs' exists" \
  || warn "Topic 'logs' not yet created — will be auto-created by Fluent Bit"

###############################################################################
# WAIT FOR VICTORIALOGS
###############################################################################
section "WAITING FOR VICTORIALOGS"

wait_for "VictoriaLogs HTTP" \
  "curl -sf http://localhost:9428/metrics" \
  20 2
success "VictoriaLogs accepting requests"

###############################################################################
# START REMAINING SERVICES
###############################################################################
section "STARTING REMAINING SERVICES"

log "Starting log generator..."
docker compose up -d generator
success "Log generator started"

log "Starting Fluent Bit..."
docker compose up -d fluentbit
success "Fluent Bit started"

log "Starting Logstash..."
docker compose up -d logstash
success "Logstash started"

log "Starting Grafana..."
docker compose up -d grafana
success "Grafana started"

###############################################################################
# WAIT FOR PIPELINE WARMUP
###############################################################################
section "PIPELINE WARMUP (60s)"

for i in $(seq 1 12); do
  sleep 5
  echo -ne "\r  ${CYAN}[$i/12] Waiting for pipeline to stabilize...${NC}"
done
echo ""

###############################################################################
# DEBUG: CONTAINER STATUS
###############################################################################
section "CONTAINER STATUS"

echo -e "${BOLD}CONTAINER            STATUS              PORTS${NC}"
echo "──────────────────────────────────────────────────────────"
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || \
docker compose ps

###############################################################################
# DEBUG: FLUENT BIT
###############################################################################
section "FLUENT BIT DIAGNOSTICS"

log "Checking Fluent Bit metrics..."
FB_METRICS=$(curl -sf http://localhost:2020/api/v1/metrics 2>/dev/null || echo "{}")
INPUT_RECORDS=$(echo "$FB_METRICS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('input',{}).get('tail.0',{}).get('records',0))" 2>/dev/null || echo "N/A")
OUTPUT_RECORDS=$(echo "$FB_METRICS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('output',{}).get('kafka.0',{}).get('proc_records',0))" 2>/dev/null || echo "N/A")
OUTPUT_ERRORS=$(echo "$FB_METRICS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('output',{}).get('kafka.0',{}).get('errors',0))" 2>/dev/null || echo "N/A")

echo -e "  Input  records : ${BOLD}$INPUT_RECORDS${NC}"
echo -e "  Output records : ${BOLD}$OUTPUT_RECORDS${NC}"
echo -e "  Output errors  : ${BOLD}$OUTPUT_ERRORS${NC}"

if [ "$OUTPUT_ERRORS" != "0" ] && [ "$OUTPUT_ERRORS" != "N/A" ]; then
  warn "Fluent Bit has output errors — check: docker logs fluentbit"
else
  success "Fluent Bit → Kafka: OK"
fi

###############################################################################
# DEBUG: KAFKA
###############################################################################
section "KAFKA DIAGNOSTICS"

log "Checking Kafka topic..."
TOPIC_EXISTS=$(docker exec kafka /opt/kafka/bin/kafka-topics.sh \
  --list --bootstrap-server localhost:9092 2>/dev/null | grep "^logs$" || echo "")

if [ -n "$TOPIC_EXISTS" ]; then
  success "Topic 'logs' exists"
  LOG_END=$(docker exec kafka /opt/kafka/bin/kafka-run-class.sh kafka.tools.GetOffsetShell \
    --broker-list localhost:9092 --topic logs --time -1 2>/dev/null | awk -F: '{print $3}' || echo "N/A")
  echo -e "  Messages in topic : ${BOLD}$LOG_END${NC}"
else
  warn "Topic 'logs' not found"
fi

log "Checking consumer groups..."
for group in $(docker exec kafka /opt/kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 --list 2>/dev/null | grep "logstash"); do
  echo ""
  echo -e "  ${BOLD}Group: $group${NC}"
  docker exec kafka /opt/kafka/bin/kafka-consumer-groups.sh \
    --bootstrap-server localhost:9092 --describe --group "$group" 2>/dev/null | \
    grep -v "^$" | sed 's/^/  /'
done

###############################################################################
# DEBUG: LOGSTASH
###############################################################################
section "LOGSTASH DIAGNOSTICS"

log "Checking Logstash pipeline..."
LS_ERRORS=$(docker logs logstash 2>&1 | grep -c "ERROR" || echo 0)
LS_400=$(docker logs logstash 2>&1 | grep -c "response_code=>400" || echo 0)
LS_RUBY=$(docker logs logstash 2>&1 | grep -c "RubyFloat" || echo 0)
LS_STARTED=$(docker logs logstash 2>&1 | grep -c "Pipeline started" || echo 0)

echo -e "  Pipeline started  : ${BOLD}$LS_STARTED${NC}"
echo -e "  ERROR count       : ${BOLD}$LS_ERRORS${NC}"
echo -e "  HTTP 400 count    : ${BOLD}$LS_400${NC}"
echo -e "  RubyFloat warns   : ${BOLD}$LS_RUBY${NC} (cosmetic — from old backlog messages)"

if [ "$LS_STARTED" -gt 0 ]; then
  success "Logstash pipeline running"
else
  error "Logstash pipeline did not start — run: docker logs logstash"
fi

if [ "$LS_400" -gt 0 ]; then
  warn "Logstash has HTTP 400 errors sending to VictoriaLogs"
fi

###############################################################################
# DEBUG: VICTORIALOGS
###############################################################################
section "VICTORIALOGS DIAGNOSTICS"

log "Querying VictoriaLogs for recent data..."
VL_RESULT=$(curl -sf \
  "http://localhost:9428/select/logsql/query?query=ingest_stage:logstash&start=1h&limit=3" \
  2>/dev/null || echo "")

if [ -n "$VL_RESULT" ]; then
  success "VictoriaLogs has data — sample records:"
  echo "$VL_RESULT" | python3 -c "
import sys, json
for line in sys.stdin:
    line = line.strip()
    if line:
        try:
            d = json.loads(line)
            print(f\"  [{d.get('_time','?')}] [{d.get('level','?')}] {d.get('node','?')} — {d.get('_msg','?')}\")
        except:
            pass
" 2>/dev/null || echo "$VL_RESULT" | head -3 | sed 's/^/  /'
else
  warn "No data in VictoriaLogs yet — pipeline may still be warming up"
  log "Try manually: curl -s 'http://localhost:9428/select/logsql/query?query=*&start=1h&limit=3'"
fi

###############################################################################
# DEBUG: GRAFANA
###############################################################################
section "GRAFANA DIAGNOSTICS"

wait_for "Grafana HTTP" \
  "curl -sf http://localhost:3000/api/health" \
  20 3

GRAFANA_STATUS=$(curl -sf http://localhost:3000/api/health 2>/dev/null | \
  python3 -c "import sys,json; print(json.load(sys.stdin).get('database','unknown'))" 2>/dev/null || echo "unknown")
echo -e "  Grafana DB status : ${BOLD}$GRAFANA_STATUS${NC}"

DS_STATUS=$(curl -sf -u admin:admin \
  "http://localhost:3000/api/datasources/name/VictoriaLogs" 2>/dev/null | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('name','not found'))" 2>/dev/null || echo "not found")

if [ "$DS_STATUS" = "VictoriaLogs" ]; then
  success "VictoriaLogs datasource provisioned in Grafana"
else
  warn "VictoriaLogs datasource not yet provisioned — plugin may still be installing"
fi

###############################################################################
# SUMMARY
###############################################################################
section "PIPELINE SUMMARY"

echo -e "
  ${BOLD}Generator${NC}     →  writing to  ./0-logs/hpc-cluster.log
  ${BOLD}Fluent Bit${NC}    →  tailing log, parsing JSON, forwarding to Kafka
  ${BOLD}Kafka${NC}         →  topic: logs  |  http://localhost:19092
  ${BOLD}Logstash${NC}      →  consuming Kafka, enriching, posting to VictoriaLogs
  ${BOLD}VictoriaLogs${NC}  →  storing logs  |  http://localhost:9428
  ${BOLD}Grafana${NC}       →  dashboards    |  http://localhost:3000  (admin/admin)

  ${BOLD}${GREEN}Query logs:${NC}
  curl -s 'http://localhost:9428/select/logsql/query?query=*&start=1h&limit=5'

  ${BOLD}${GREEN}Consumer lag:${NC}
  docker exec kafka /opt/kafka/bin/kafka-consumer-groups.sh \\
    --bootstrap-server localhost:9092 --describe --group <group_id>

  ${BOLD}${GREEN}Live Fluent Bit metrics:${NC}
  curl -s http://localhost:2020/api/v1/metrics
"

success "Pipeline startup complete 🚀"