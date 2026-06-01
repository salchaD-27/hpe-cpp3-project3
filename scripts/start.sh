# #!/bin/bash
# set -e

# SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# cd "$SCRIPT_DIR"

# # Colors for output
# RED='\033[0;31m'
# GREEN='\033[0;32m'
# YELLOW='\033[1;33m'
# BLUE='\033[0;34m'
# CYAN='\033[0;36m'
# BOLD='\033[1m'
# NC='\033[0m'

# log() { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"; }
# ok() { echo -e "${GREEN}[OK]${NC} $1"; }
# warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
# err() { echo -e "${RED}[ERROR]${NC} $1"; }
# header() { echo -e "\n${BOLD}${CYAN}=== $1 ===${NC}"; }

# wait_for() {
#     local label=$1 cmd=$2 retries=${3:-30} delay=${4:-2}
#     log "Waiting for $label"
#     for i in $(seq 1 $retries); do
#         eval "$cmd" &>/dev/null && { ok "$label ready"; return 0; }
#         sleep $delay
#     done
#     err "$label not ready"
#     return 1
# }

# # Port check
# check_ports() {
#     header "PORT VERIFICATION"
#     PORTS=(8001 8002 8003 8004 8005 8006 8081 8881 3001 9094 9601)
#     for port in "${PORTS[@]}"; do
#         if lsof -i :$port -sTCP:LISTEN &>/dev/null; then
#             err "Port $port already in use"
#             exit 1
#         else
#             ok "Port $port available"
#         fi
#     done
# }

# # Build
# build_log_gen() {
#     header "BUILDING LOG GENERATOR"
#     log "Building log generator image"
#     cd node-1-ingest/1-log-gen
#     docker build -t log-generator:latest . >/dev/null 2>&1
#     cd "$SCRIPT_DIR"
#     ok "Log generator image built"
# }

# # Start storage
# start_storage() {
#     header "STARTING STORAGE NODES (Node 2 & 3)"
#     log "Starting Node 2 (Storage Node 1)"
#     cd node-2-storage && docker-compose up -d >/dev/null 2>&1 && cd ..
#     ok "Node 2 started"
    
#     log "Starting Node 3 (Storage Node 2)"
#     cd node-3-storage && docker-compose up -d >/dev/null 2>&1 && cd ..
#     ok "Node 3 started"
    
#     wait_for "storage nodes" "curl -s http://localhost:8002/metrics >/dev/null && curl -s http://localhost:8003/metrics >/dev/null" 15 2
# }

# # Start ingestion
# start_ingestion() {
#     header "STARTING INGESTION NODE (Node 1)"
#     log "Starting Node 1 (Ingestion Pipeline)"
#     cd node-1-ingest && docker-compose up -d >/dev/null 2>&1 && cd ..
    
#     wait_for "Kafka" "docker exec node-1-kafka /opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092 >/dev/null 2>&1" 30 3
#     wait_for "Logstash" "curl -s http://localhost:9601/_node/stats >/dev/null 2>&1" 30 2
#     wait_for "vlinsert" "curl -s http://localhost:8001/metrics >/dev/null 2>&1" 15 2
    
#     ok "Node 1 fully operational"
# }

# # Start query
# start_query() {
#     header "STARTING QUERY NODE (Node 4)"
#     log "Starting Node 4 (Query + Alerting)"
#     cd node-4-query && docker-compose up -d >/dev/null 2>&1 && cd ..
    
#     wait_for "vlselect" "curl -s http://localhost:8004/metrics >/dev/null 2>&1" 15 2

#     # Grafana takes longer on first boot due to plugin installation.
#     if ! wait_for "Grafana" "curl -s http://localhost:3001/api/health >/dev/null 2>&1" 90 2; then
#         warn "Dumping Grafana logs for diagnosis"
#         docker logs --tail 200 node-4-grafana 2>/dev/null || true
#         err "Grafana not ready"
#         return 1
#     fi

#     wait_for "vmalert" "curl -s http://localhost:8881/-/healthy >/dev/null 2>&1" 15 2
    
#     ok "Node 4 fully operational"
# }

# # Start orchestrator
# start_orchestrator() {
#     header "STARTING ORCHESTRATOR NODE (Node 5)"
#     log "Starting Node 5 (Load Balancer + Backup)"
#     if [ -d "node-5-orch" ]; then
#         cd node-5-orch && docker-compose up -d >/dev/null 2>&1 && cd ..
#     else
#         err "node-5-orch directory not found (expected: node-5-orch/)"
#         return 1
#     fi

    
#     wait_for "Nginx" "curl -s http://localhost:8005/ >/dev/null 2>&1" 15 2
#     wait_for "Backup vlselect" "curl -s http://localhost:8006/metrics >/dev/null 2>&1" 15 2
    
#     ok "Node 5 fully operational"
# }

# # Show status
# show_status() {
#     header "PIPELINE STATUS"
    
#     # Container status
#     echo -e "${BOLD}Containers:${NC}"
#     docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | grep -E "node-|NAMES" | sed 's/^/  /'
    
#     # Storage distribution
#     echo ""
#     echo -e "${BOLD}Storage Distribution:${NC}"
#     N2=$(curl -s 'http://localhost:8002/select/logsql/query?query=*%20%7C%20count()' 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('count(*)',0))" 2>/dev/null || echo "0")
#     N3=$(curl -s 'http://localhost:8003/select/logsql/query?query=*%20%7C%20count()' 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('count(*)',0))" 2>/dev/null || echo "0")
#     LB=$(curl -s 'http://localhost:8005/select/logsql/query?query=*%20%7C%20count()' 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('count(*)',0))" 2>/dev/null || echo "0")
    
#     echo "  Node 2 (Storage 1): $N2 logs"
#     echo "  Node 3 (Storage 2): $N3 logs"
#     echo "  Total Storage:        $((N2 + N3)) logs"
#     echo "  Load Balancer:        $LB logs"
    
#     if [ "$LB" -eq "$((N2 + N3))" ] && [ "$((N2 + N3))" -gt 0 ]; then
#         echo "  Data Consistency:     PASSED"
#     else
#         echo "  Data Consistency:     FAILED"
#     fi
    
#     # Pipeline metrics
#     echo ""
#     echo -e "${BOLD}Pipeline Metrics:${NC}"
#     FB=$(curl -s http://localhost:8081/api/v1/metrics 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('input',{}).get('tail.0',{}).get('records',0))" 2>/dev/null || echo "0")
#     LS=$(curl -s http://localhost:9601/_node/stats 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('pipelines',{}).get('main',{}).get('events',{}).get('out',0))" 2>/dev/null || echo "0")
#     THROUGHPUT=$(curl -s http://localhost:9601/_node/stats 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('pipelines',{}).get('main',{}).get('flow',{}).get('output_throughput',{}).get('current',0))" 2>/dev/null || echo "0")
    
#     echo "  Fluent Bit Records:   $FB"
#     echo "  Logstash Events Out:  $LS"
#     echo "  Logstash Throughput:  $THROUGHPUT events/sec"
# }

# # Show access points
# show_access() {
#     header "ACCESS POINTS"
    
#     echo -e "${BOLD}Grafana Dashboard:${NC}"
#     echo "  Grafana UI:           http://localhost:3001 (admin/admin)"
#     echo "  VictoriaLogs Datasource: http://localhost:8005"
#     echo ""
#     echo -e "${BOLD}Alerting:${NC}"
#     echo "  vmalert UI:           http://localhost:8881"
#     echo "  vmalert API:          http://localhost:8881/api/v1/alerts"
#     echo ""
#     echo -e "${BOLD}Direct Storage Access:${NC}"
#     echo "  Node 2 (Storage 1): http://localhost:8002"
#     echo "  Node 3 (Storage 2): http://localhost:8003"
#     echo "  Load Balancer:        http://localhost:8005"
#     echo ""
#     echo -e "${BOLD}Pipeline Monitoring:${NC}"
#     echo "  Fluent Bit Metrics:   http://localhost:8081/api/v1/metrics"
#     echo "  Logstash API:         http://localhost:9601/_node/stats"
#     echo "  Kafka:                http://localhost:9094"
# }

# # Demo commands
# show_demo_commands() {
#     header "DEMO COMMANDS"
#     echo ""
#     echo "# Check total logs"
#     echo "curl -s 'http://localhost:8005/select/logsql/query?query=*%20%7C%20count()' | jq"
#     echo ""
#     echo "# Check storage distribution"
#     echo "curl -s 'http://localhost:8002/select/logsql/query?query=*%20%7C%20count()'"
#     echo "curl -s 'http://localhost:8003/select/logsql/query?query=*%20%7C%20count()'"
#     echo ""
#     echo "# View recent error logs"
#     echo "curl -s 'http://localhost:8005/select/logsql/query?query=level:ERROR%20%7C%20limit%2010' | jq ."
#     echo ""
#     echo "# Check vmalert alerts"
#     echo "curl -s 'http://localhost:8881/api/v1/alerts' | jq '.data.alerts[] | {name: .name, state: .state}'"
# }

# # Main
# main() {
#     echo ""
#     log "Starting Multi-Node VictoriaLogs Pipeline"
#     echo ""
    
#     check_ports
#     build_log_gen
#     start_storage
#     start_ingestion
#     start_query
#     start_orchestrator
    
#     log "Waiting for pipeline to stabilize"
#     sleep 30
    
#     show_status
#     show_access
#     show_demo_commands
    
#     echo ""
#     ok "Pipeline startup complete"
#     echo ""
# }

# main
















# #!/bin/bash
# # =============================================================================
# # start.sh — 5-Node HPC Log Pipeline
# # Startup order: storage → write-gateway → query → pipeline
# # =============================================================================
# set -e

# SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# cd "$SCRIPT_DIR/.."

# RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
# BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# log()    { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"; }
# ok()     { echo -e "${GREEN}[OK]${NC} $1"; }
# warn()   { echo -e "${YELLOW}[WARN]${NC} $1"; }
# err()    { echo -e "${RED}[ERROR]${NC} $1"; }
# header() { echo -e "\n${BOLD}${CYAN}=== $1 ===${NC}"; }

# wait_for() {
#     local label=$1 cmd=$2 retries=${3:-30} delay=${4:-2}
#     log "Waiting for $label"
#     for i in $(seq 1 $retries); do
#         eval "$cmd" &>/dev/null && { ok "$label ready"; return 0; }
#         sleep "$delay"
#     done
#     err "$label not ready after $((retries * delay))s"
#     return 1
# }

# check_ports() {
#     header "PORT VERIFICATION"
#     local PORTS=(8001 8002 8003 8004 8080 8081 8428 8881 3001 9094 9095 9601)
#     for port in "${PORTS[@]}"; do
#         # Only fail if port is taken by something other than our docker containers.
#         if lsof -i :"$port" -sTCP:LISTEN -n -P 2>/dev/null | grep -qv '^com\.docke'; then
#             err "Port $port already in use"; exit 1
#         else
#             ok "Port $port available"
#         fi
#     done
# }

# start_storage() {
#     header "STARTING STORAGE NODES (Node 3 & 4)"
#     log "Starting Node 3 (vlstorage 1)"
#     (cd node-3-vlstorage && docker compose up -d) >/dev/null 2>&1
#     ok "Node 3 started"

#     log "Starting Node 4 (vlstorage 2)"
#     (cd node-4-vlstorage && docker compose up -d) >/dev/null 2>&1
#     ok "Node 4 started"

#     wait_for "storage nodes" \
#         "curl -sf http://localhost:8002/metrics >/dev/null && curl -sf http://localhost:8003/metrics >/dev/null" \
#         15 2
# }

# start_write_gateway() {
#     header "STARTING WRITE GATEWAY (Node 2 — vlinsert)"
#     (cd node-2-vlinsert && docker compose up -d) >/dev/null 2>&1
#     wait_for "vlinsert" "curl -sf http://localhost:8001/metrics >/dev/null" 15 2
#     ok "Node 2 fully operational"
# }

# start_query() {
#     header "STARTING QUERY NODE (Node 5 — vlselect)"
#     (cd node-5-vlselect && docker compose up -d) >/dev/null 2>&1
#     wait_for "vlselect" "curl -sf http://localhost:8004/metrics >/dev/null" 15 2
#     ok "Node 5 fully operational"
# }

# start_pipeline() {
#     header "STARTING PIPELINE NODE (Node 1)"
#     (cd node-1-pipeline && docker compose up -d) >/dev/null 2>&1

#     wait_for "Kafka" \
#         "docker exec node-1-kafka /opt/kafka/bin/kafka-topics.sh --list --bootstrap-server node-1-kafka:9092 >/dev/null 2>&1" \
#         60 3

#     # Logstash readiness: API endpoint is /_node/stats but the server can still be warming up.
#     # Increase retries and add a tiny log dump on failure to avoid hanging forever.
#     wait_for "Logstash" "curl -sf http://localhost:9601/_node/stats >/dev/null" 90 2
#     wait_for "Grafana"  "curl -sf http://localhost:3001/api/health >/dev/null" 180 2
#     wait_for "vmalert"  "curl -sf http://localhost:8881/-/healthy >/dev/null" 30 2
#     wait_for "Alertmanager" "curl -sf http://localhost:9095/ >/dev/null" 30 2

#     ok "Node 1 fully operational"
# }

# show_status() {
#     header "PIPELINE STATUS"

#     echo -e "${BOLD}Containers:${NC}"
#     docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null \
#         | grep -E "node-[1-5]|NAMES" | sed 's/^/  /'

#     echo ""
#     echo -e "${BOLD}Storage Distribution:${NC}"
#     N3=$(curl -sf 'http://localhost:8002/select/logsql/query?query=*%20%7C%20count()' \
#         2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(list(d.values())[0] if d else 0)" 2>/dev/null || echo "0")
#     N4=$(curl -sf 'http://localhost:8003/select/logsql/query?query=*%20%7C%20count()' \
#         2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(list(d.values())[0] if d else 0)" 2>/dev/null || echo "0")
#     echo "  Node 3 (vlstorage 1): $N3 logs"
#     echo "  Node 4 (vlstorage 2): $N4 logs"
#     echo "  Total via vlselect:   $(curl -sf 'http://localhost:8004/select/logsql/query?query=*%20%7C%20count()' \
#         2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(list(d.values())[0] if d else 0)" 2>/dev/null || echo "0") logs"
# }

# show_access() {
#     header "ACCESS POINTS"
#     cat << 'EOF'
#   Grafana UI:           http://localhost:3001  (admin / admin)
#   Kafka UI:             http://localhost:8080
#   vmalert UI:           http://localhost:8881
#   Alertmanager UI:      http://localhost:9095
#   VictoriaMetrics:      http://localhost:8428

#   Write API (vlinsert): http://localhost:8001
#   Query API (vlselect): http://localhost:8004
#   Storage Node 3:       http://localhost:8002
#   Storage Node 4:       http://localhost:8003

#   Fluent Bit metrics:   http://localhost:2020/api/v1/metrics
#   Logstash API:         http://localhost:9601/_node/stats
#   Kafka (external):     localhost:9094
# EOF
# }

# main() {
#     echo ""
#     log "Starting 5-Node HPC Log Pipeline (1-2-2 architecture)"
#     echo ""

#     log "Creating shared Docker network"
#     docker network inspect multi-node-net >/dev/null 2>&1 \
#         || docker network create multi-node-net
#     ok "Network multi-node-net ready"

#     check_ports
#     start_storage        # Node 3, 4  — must be up before vlinsert/vlselect
#     start_write_gateway  # Node 2
#     start_query          # Node 5
#     start_pipeline       # Node 1

#     log "Waiting for pipeline to stabilise"
#     sleep 54

#     show_status
#     show_access

#     echo ""
#     ok "Pipeline startup complete"
#     echo ""
# }

# main




#!/bin/bash
# =============================================================================
# start.sh — 5-Node HPC Log Pipeline (JSON Only)
# Startup order: storage → write-gateway → query → pipeline
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"


# Colors for output
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

build_log_gen() {
    header "BUILDING LOG GENERATOR"
    log "Building log generator image"
    cd "$REPO_ROOT/node-1-pipeline/1-generator"
    # generator.py runs directly in the pipeline container; this build is optional.
    # Keep the build step only if the directory contains a Dockerfile.
    if [ -f Dockerfile ]; then
        docker build -t log-generator:latest . >/dev/null 2>&1
        ok "Log generator image built"
    else
        warn "No Dockerfile in node-1-pipeline/1-generator — skipping image build"
    fi
    cd "$SCRIPT_DIR"
}

start_storage() {
    header "STARTING STORAGE NODES (Node 3 & 4)"
    
    log "Starting Node 3 (vlstorage 1)"
    (cd "$REPO_ROOT/node-3-vlstorage" && docker compose up -d) >/dev/null 2>&1
    ok "Node 3 started"

    log "Starting Node 4 (vlstorage 2)"
    (cd "$REPO_ROOT/node-4-vlstorage" && docker compose up -d) >/dev/null 2>&1
    ok "Node 4 started"

    wait_for "storage nodes" \
        "curl -sf http://localhost:8002/metrics >/dev/null && curl -sf http://localhost:8003/metrics >/dev/null" \
        15 2
}

start_write_gateway() {
    header "STARTING WRITE GATEWAY (Node 2 — vlinsert)"
    (cd "$REPO_ROOT/node-2-vlinsert" && docker compose up -d) >/dev/null 2>&1
    wait_for "vlinsert" "curl -sf http://localhost:8001/metrics >/dev/null" 15 2
    ok "Node 2 fully operational"
}

start_query() {
    header "STARTING QUERY NODE (Node 5 — vlselect)"
    (cd "$REPO_ROOT/node-5-vlselect" && docker compose up -d) >/dev/null 2>&1
    wait_for "vlselect" "curl -sf http://localhost:8004/metrics >/dev/null" 15 2
    ok "Node 5 fully operational"
}

start_pipeline() {
    header "STARTING PIPELINE NODE (Node 1)"
    (cd "$REPO_ROOT/node-1-pipeline" && docker compose up -d) >/dev/null 2>&1

    # Wait for Kafka (use container name, not localhost)
    wait_for "Kafka" \
        "docker exec node-1-kafka /opt/kafka/bin/kafka-topics.sh --list --bootstrap-server node-1-kafka:9092 >/dev/null 2>&1" \
        60 3

    # Wait for Logstash
    wait_for "Logstash" "curl -sf http://localhost:9601/_node/stats >/dev/null" 90 2
    
    # Wait for Grafana (takes longer on first boot for plugin installation)
    if ! wait_for "Grafana" "curl -sf http://localhost:3001/api/health >/dev/null" 180 2; then
        warn "Grafana may still be starting, continuing..."
    fi
    
    # Wait for vmalert
    wait_for "vmalert" "curl -sf http://localhost:8881/-/healthy >/dev/null" 30 2
    
    # Wait for Alertmanager
    wait_for "Alertmanager" "curl -sf http://localhost:9095/ >/dev/null" 30 2

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
    TOTAL=$(curl -sf 'http://localhost:8004/select/logsql/query?query=*%20%7C%20count()' \
        2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(list(d.values())[0] if d else 0)" 2>/dev/null || echo "0")
    
    echo "  Node 3 (vlstorage 1): $N3 logs"
    echo "  Node 4 (vlstorage 2): $N4 logs"
    echo "  Total via vlselect:   $TOTAL logs"
    
    # Pipeline metrics
    echo ""
    echo -e "${BOLD}Pipeline Metrics:${NC}"
    FB=$(curl -s http://localhost:8081/api/v1/metrics 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('input',{}).get('tail.0',{}).get('records',0))" 2>/dev/null || echo "0")
    LS=$(curl -s http://localhost:9601/_node/stats 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('pipelines',{}).get('main',{}).get('events',{}).get('out',0))" 2>/dev/null || echo "0")
    
    echo "  Fluent Bit Records:   $FB"
    echo "  Logstash Events Out:  $LS"
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

    # Create shared Docker network
    log "Creating shared Docker network"
    docker network inspect multi-node-net >/dev/null 2>&1 \
        || docker network create multi-node-net
    ok "Network multi-node-net ready"

    check_ports
    build_log_gen
    start_storage        # Node 3, 4 — must be up before vlinsert/vlselect
    start_write_gateway  # Node 2
    start_query          # Node 5
    start_pipeline       # Node 1

    log "Waiting for pipeline to stabilize"
    sleep 30

    show_status
    show_access

    echo ""
    ok "Pipeline startup complete"
    echo ""
}

main