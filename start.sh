#!/bin/bash
# =============================================================================
# start.sh — 5-Node HPC Log Pipeline (JSON Only)
# Startup order: storage → write-gateway → query → pipeline
# =============================================================================
set -e

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

log() { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"; }
ok() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err() { echo -e "${RED}[ERROR]${NC} $1"; }
header() { echo -e "\n${BOLD}${CYAN}=== $1 ===${NC}"; }

wait_for() {
    local label=$1 cmd=$2 retries=${3:-60} delay=${4:-2}
    log "Waiting for $label"
    for i in $(seq 1 $retries); do
        if eval "$cmd" 2>/dev/null; then
            ok "$label ready"
            return 0
        fi
        sleep "$delay"
    done
    warn "$label not ready after $((retries * delay))s, continuing..."
    return 0
}

check_ports() {
    header "PORT VERIFICATION"
    local PORTS=(8001 8002 8003 8004 8080 8081 8881 3001 9094 9095 9601)
    for port in "${PORTS[@]}"; do
        if lsof -i :"$port" -sTCP:LISTEN 2>/dev/null | grep -vq '^com\.docke'; then
            err "Port $port already in use"
            exit 1
        else
            ok "Port $port available"
        fi
    done
}

ensure_storage_dirs() {
    log "Creating storage directories..."
    mkdir -p "$SCRIPT_DIR/node-3-vlstorage/storage"
    mkdir -p "$SCRIPT_DIR/node-4-vlstorage/storage"
    ok "Storage directories ready"
}

# Create shared network
log "Creating shared Docker network"
docker network inspect multi-node-net >/dev/null 2>&1 || docker network create multi-node-net
ok "Network multi-node-net ready"

ensure_storage_dirs
check_ports

# =============================================================================
# START STORAGE NODES (Node 3 & 4)
# =============================================================================
header "STARTING STORAGE NODES (Node 3 & 4)"

log "Starting Node 3 (vlstorage 1)"
cd "$SCRIPT_DIR/node-3-vlstorage"
docker compose up -d
cd "$SCRIPT_DIR"
ok "Node 3 started"

log "Starting Node 4 (vlstorage 2)"
cd "$SCRIPT_DIR/node-4-vlstorage"
docker compose up -d
cd "$SCRIPT_DIR"
ok "Node 4 started"

wait_for "storage nodes" \
    "curl -sf http://localhost:8002/metrics >/dev/null && curl -sf http://localhost:8003/metrics >/dev/null" \
    20 2

# =============================================================================
# START WRITE GATEWAY
# =============================================================================
header "STARTING WRITE GATEWAY (Node 2 — vlinsert)"
cd "$SCRIPT_DIR/node-2-vlinsert"
docker compose up -d
cd "$SCRIPT_DIR"
wait_for "vlinsert" "curl -sf http://localhost:8001/metrics >/dev/null" 15 2
ok "Node 2 fully operational"

# =============================================================================
# START QUERY NODE
# =============================================================================
header "STARTING QUERY NODE (Node 5 — vlselect)"
cd "$SCRIPT_DIR/node-5-vlselect"
docker compose up -d
cd "$SCRIPT_DIR"
wait_for "vlselect" "curl -sf http://localhost:8004/metrics >/dev/null" 15 2
ok "Node 5 fully operational"

# =============================================================================
# START PIPELINE NODE
# =============================================================================
header "STARTING PIPELINE NODE (Node 1)"

mkdir -p "$SCRIPT_DIR/node-1-pipeline/1-generator/logs-generated"

cd "$SCRIPT_DIR/node-1-pipeline"
docker compose up -d
cd "$SCRIPT_DIR"

# Wait for Kafka
log "Waiting for Kafka..."
for i in $(seq 1 90); do
    if docker exec node-1-kafka /opt/kafka/bin/kafka-topics.sh --list --bootstrap-server node-1-kafka:9092 2>/dev/null; then
        ok "Kafka ready"
        break
    fi
    if [ $i -eq 90 ]; then
        warn "Kafka not ready after 90 seconds, continuing..."
    fi
    sleep 1
done

# Wait for Logstash
log "Waiting for Logstash..."
for i in $(seq 1 60); do
    if curl -sf http://localhost:9601/_node/stats >/dev/null 2>&1; then
        ok "Logstash ready"
        break
    fi
    sleep 1
done

# Wait for Grafana
log "Waiting for Grafana..."
for i in $(seq 1 180); do
    if curl -sf http://localhost:3001/api/health >/dev/null 2>&1; then
        ok "Grafana ready"
        break
    fi
    sleep 1
done

# Wait for vmalert
log "Waiting for vmalert..."
for i in $(seq 1 30); do
    if curl -sf http://localhost:8881/-/healthy >/dev/null 2>&1; then
        ok "vmalert ready"
        break
    fi
    sleep 1
done

# Wait for Alertmanager
log "Waiting for Alertmanager..."
for i in $(seq 1 30); do
    if curl -sf http://localhost:9095/ >/dev/null 2>&1; then
        ok "Alertmanager ready"
        break
    fi
    sleep 1
done

ok "Node 1 fully operational"

log "Waiting for pipeline to stabilize"
sleep 30

# =============================================================================
# SHOW STATUS
# =============================================================================
header "PIPELINE STATUS"

echo -e "${BOLD}Containers:${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | head -20 | sed 's/^/  /'

echo ""
echo -e "${BOLD}Storage Distribution:${NC}"

N3=$(curl -sf 'http://localhost:8002/select/logsql/query?query=*%20%7C%20count()' 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(list(d.values())[0] if d else 0)" 2>/dev/null || echo "0")
N4=$(curl -sf 'http://localhost:8003/select/logsql/query?query=*%20%7C%20count()' 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(list(d.values())[0] if d else 0)" 2>/dev/null || echo "0")
TOTAL=$(curl -sf 'http://localhost:8004/select/logsql/query?query=*%20%7C%20count()' 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(list(d.values())[0] if d else 0)" 2>/dev/null || echo "0")

echo "  Node 3 (vlstorage 1): $N3 logs"
echo "  Node 4 (vlstorage 2): $N4 logs"
echo "  Total via vlselect:   $TOTAL logs"

show_access() {
    header "ACCESS POINTS"
    cat << 'EOF'
    Grafana UI:           http://localhost:3001  (admin / admin)
    vmalert UI:           http://localhost:8881
    Alertmanager UI:      http://localhost:9095

    Write API:            http://localhost:8001
    Query API:            http://localhost:8004
    Storage Node 3:       http://localhost:8002
    Storage Node 4:       http://localhost:8003

    Fluent Bit metrics:   http://localhost:2020/api/v1/metrics
    Logstash API:         http://localhost:9601/_node/stats
    Kafka (external):     localhost:9094
EOF
}

show_access

echo ""
ok "Pipeline startup complete"
echo ""