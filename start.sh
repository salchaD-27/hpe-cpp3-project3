#!/bin/bash
# =============================================================================
# start.sh — 5-Node HPC Log Pipeline
# Startup order: storage → write-gateway → query → pipeline
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()    { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"; }
ok()     { echo -e "${GREEN}[OK]${NC} $1"; }
warn()   { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()    { echo -e "${RED}[ERROR]${NC} $1"; }
header() { echo -e "\n${BOLD}${CYAN}=== $1 ===${NC}"; }

wait_for() {
    local label=$1 cmd=$2 retries=${3:-30} delay=${4:-2}
    log "Waiting for $label"
    for i in $(seq 1 $retries); do
        eval "$cmd" &>/dev/null && { ok "$label ready"; return 0; }
        sleep "$delay"
    done
    err "$label not ready after $((retries * delay))s"
    return 1
}

check_ports() {
    header "PORT VERIFICATION"
    local PORTS=(8001 8002 8003 8004 8080 8081 8428 8881 3001 9094 9095 9601)
    for port in "${PORTS[@]}"; do
        if lsof -i :"$port" -sTCP:LISTEN &>/dev/null 2>&1; then
            err "Port $port already in use"; exit 1
        else
            ok "Port $port available"
        fi
    done
}

start_storage() {
    header "STARTING STORAGE NODES (Node 3 & 4)"
    log "Starting Node 3 (vlstorage 1)"
    (cd node-3-vlstorage && docker compose up -d) >/dev/null 2>&1
    ok "Node 3 started"

    log "Starting Node 4 (vlstorage 2)"
    (cd node-4-vlstorage && docker compose up -d) >/dev/null 2>&1
    ok "Node 4 started"

    wait_for "storage nodes" \
        "curl -sf http://localhost:8002/metrics >/dev/null && curl -sf http://localhost:8003/metrics >/dev/null" \
        15 2
}

start_write_gateway() {
    header "STARTING WRITE GATEWAY (Node 2 — vlinsert)"
    (cd node-2-vlinsert && docker compose up -d) >/dev/null 2>&1
    wait_for "vlinsert" "curl -sf http://localhost:8001/metrics >/dev/null" 15 2
    ok "Node 2 fully operational"
}

start_query() {
    header "STARTING QUERY NODE (Node 5 — vlselect)"
    (cd node-5-vlselect && docker compose up -d) >/dev/null 2>&1
    wait_for "vlselect" "curl -sf http://localhost:8004/metrics >/dev/null" 15 2
    ok "Node 5 fully operational"
}

start_pipeline() {
    header "STARTING PIPELINE NODE (Node 1)"
    (cd node-1-pipeline && docker compose up -d) >/dev/null 2>&1

    wait_for "Kafka" \
        "docker exec node-1-kafka /opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092 >/dev/null 2>&1" \
        30 3
    wait_for "Logstash" "curl -sf http://localhost:9601/_node/stats >/dev/null" 45 3
    wait_for "Grafana"  "curl -sf http://localhost:3001/api/health >/dev/null" 90 2
    wait_for "vmalert"  "curl -sf http://localhost:8881/-/healthy >/dev/null" 15 2
    wait_for "Alertmanager" "curl -sf http://localhost:9095/ >/dev/null" 15 2

    ok "Node 1 fully operational"
}

show_status() {
    header "PIPELINE STATUS"

    echo -e "${BOLD}Containers:${NC}"
    docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null \
        | grep -E "node-[1-5]|NAMES" | sed 's/^/  /'

    echo ""
    echo -e "${BOLD}Storage Distribution:${NC}"
    N3=$(curl -sf 'http://localhost:8002/select/logsql/query?query=*%20%7C%20count()' \
        2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(list(d.values())[0] if d else 0)" 2>/dev/null || echo "0")
    N4=$(curl -sf 'http://localhost:8003/select/logsql/query?query=*%20%7C%20count()' \
        2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(list(d.values())[0] if d else 0)" 2>/dev/null || echo "0")
    echo "  Node 3 (vlstorage 1): $N3 logs"
    echo "  Node 4 (vlstorage 2): $N4 logs"
    echo "  Total via vlselect:   $(curl -sf 'http://localhost:8004/select/logsql/query?query=*%20%7C%20count()' \
        2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(list(d.values())[0] if d else 0)" 2>/dev/null || echo "0") logs"
}

show_access() {
    header "ACCESS POINTS"
    cat << 'EOF'
  Grafana UI:           http://localhost:3001  (admin / admin)
  Kafka UI:             http://localhost:8080
  vmalert UI:           http://localhost:8881
  Alertmanager UI:      http://localhost:9095
  VictoriaMetrics:      http://localhost:8428

  Write API (vlinsert): http://localhost:8001
  Query API (vlselect): http://localhost:8004
  Storage Node 3:       http://localhost:8002
  Storage Node 4:       http://localhost:8003

  Fluent Bit metrics:   http://localhost:2020/api/v1/metrics
  Logstash API:         http://localhost:9601/_node/stats
  Kafka (external):     localhost:9094
EOF
}

main() {
    echo ""
    log "Starting 5-Node HPC Log Pipeline (1-2-2 architecture)"
    echo ""

    log "Creating shared Docker network"
    docker network inspect multi-node-net >/dev/null 2>&1 \
        || docker network create multi-node-net
    ok "Network multi-node-net ready"

    check_ports
    start_storage        # Node 3, 4  — must be up before vlinsert/vlselect
    start_write_gateway  # Node 2
    start_query          # Node 5
    start_pipeline       # Node 1

    log "Waiting 20s for pipeline to stabilise"
    sleep 20

    show_status
    show_access

    echo ""
    ok "Pipeline startup complete"
    echo ""
}

main
