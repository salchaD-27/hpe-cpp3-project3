#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

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
        sleep $delay
    done
    err "$label not ready"
    return 1
}

# Port check
check_ports() {
    header "PORT VERIFICATION"
    PORTS=(8001 8002 8003 8004 8005 8006 8081 8881 3001 9094 9601)
    for port in "${PORTS[@]}"; do
        if lsof -i :$port -sTCP:LISTEN &>/dev/null; then
            err "Port $port already in use"
            exit 1
        else
            ok "Port $port available"
        fi
    done
}

# Build
build_log_gen() {
    header "BUILDING LOG GENERATOR"
    log "Building log generator image"
    cd node-1-ingest/1-log-gen
    docker build -t log-generator:latest . >/dev/null 2>&1
    cd "$SCRIPT_DIR"
    ok "Log generator image built"
}

# Start storage
start_storage() {
    header "STARTING STORAGE NODES (Node 2 & 3)"
    log "Starting Node 2 (Storage Node 1)"
    cd node-2-storage && docker-compose up -d >/dev/null 2>&1 && cd ..
    ok "Node 2 started"
    
    log "Starting Node 3 (Storage Node 2)"
    cd node-3-storage && docker-compose up -d >/dev/null 2>&1 && cd ..
    ok "Node 3 started"
    
    wait_for "storage nodes" "curl -s http://localhost:8002/metrics >/dev/null && curl -s http://localhost:8003/metrics >/dev/null" 15 2
}

# Start ingestion
start_ingestion() {
    header "STARTING INGESTION NODE (Node 1)"
    log "Starting Node 1 (Ingestion Pipeline)"
    cd node-1-ingest && docker-compose up -d >/dev/null 2>&1 && cd ..
    
    wait_for "Kafka" "docker exec node-1-kafka /opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092 >/dev/null 2>&1" 30 3
    wait_for "Logstash" "curl -s http://localhost:9601/_node/stats >/dev/null 2>&1" 30 2
    wait_for "vlinsert" "curl -s http://localhost:8001/metrics >/dev/null 2>&1" 15 2
    
    ok "Node 1 fully operational"
}

# Start query
start_query() {
    header "STARTING QUERY NODE (Node 4)"
    log "Starting Node 4 (Query + Alerting)"
    cd node-4-query && docker-compose up -d >/dev/null 2>&1 && cd ..
    
    wait_for "vlselect" "curl -s http://localhost:8004/metrics >/dev/null 2>&1" 15 2

    # Grafana takes longer on first boot due to plugin installation.
    if ! wait_for "Grafana" "curl -s http://localhost:3001/api/health >/dev/null 2>&1" 90 2; then
        warn "Dumping Grafana logs for diagnosis"
        docker logs --tail 200 node-4-grafana 2>/dev/null || true
        err "Grafana not ready"
        return 1
    fi

    wait_for "vmalert" "curl -s http://localhost:8881/-/healthy >/dev/null 2>&1" 15 2
    
    ok "Node 4 fully operational"
}

# Start orchestrator
start_orchestrator() {
    header "STARTING ORCHESTRATOR NODE (Node 5)"
    log "Starting Node 5 (Load Balancer + Backup)"
    if [ -d "node-5-orch" ]; then
        cd node-5-orch && docker-compose up -d >/dev/null 2>&1 && cd ..
    else
        err "node-5-orch directory not found (expected: node-5-orch/)"
        return 1
    fi

    
    wait_for "Nginx" "curl -s http://localhost:8005/ >/dev/null 2>&1" 15 2
    wait_for "Backup vlselect" "curl -s http://localhost:8006/metrics >/dev/null 2>&1" 15 2
    
    ok "Node 5 fully operational"
}

# Show status
show_status() {
    header "PIPELINE STATUS"
    
    # Container status
    echo -e "${BOLD}Containers:${NC}"
    docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | grep -E "node-|NAMES" | sed 's/^/  /'
    
    # Storage distribution
    echo ""
    echo -e "${BOLD}Storage Distribution:${NC}"
    N2=$(curl -s 'http://localhost:8002/select/logsql/query?query=*%20%7C%20count()' 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('count(*)',0))" 2>/dev/null || echo "0")
    N3=$(curl -s 'http://localhost:8003/select/logsql/query?query=*%20%7C%20count()' 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('count(*)',0))" 2>/dev/null || echo "0")
    LB=$(curl -s 'http://localhost:8005/select/logsql/query?query=*%20%7C%20count()' 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('count(*)',0))" 2>/dev/null || echo "0")
    
    echo "  Node 2 (Storage 1): $N2 logs"
    echo "  Node 3 (Storage 2): $N3 logs"
    echo "  Total Storage:        $((N2 + N3)) logs"
    echo "  Load Balancer:        $LB logs"
    
    if [ "$LB" -eq "$((N2 + N3))" ] && [ "$((N2 + N3))" -gt 0 ]; then
        echo "  Data Consistency:     PASSED"
    else
        echo "  Data Consistency:     FAILED"
    fi
    
    # Pipeline metrics
    echo ""
    echo -e "${BOLD}Pipeline Metrics:${NC}"
    FB=$(curl -s http://localhost:8081/api/v1/metrics 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('input',{}).get('tail.0',{}).get('records',0))" 2>/dev/null || echo "0")
    LS=$(curl -s http://localhost:9601/_node/stats 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('pipelines',{}).get('main',{}).get('events',{}).get('out',0))" 2>/dev/null || echo "0")
    THROUGHPUT=$(curl -s http://localhost:9601/_node/stats 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('pipelines',{}).get('main',{}).get('flow',{}).get('output_throughput',{}).get('current',0))" 2>/dev/null || echo "0")
    
    echo "  Fluent Bit Records:   $FB"
    echo "  Logstash Events Out:  $LS"
    echo "  Logstash Throughput:  $THROUGHPUT events/sec"
}

# Show access points
show_access() {
    header "ACCESS POINTS"
    
    echo -e "${BOLD}Grafana Dashboard:${NC}"
    echo "  Grafana UI:           http://localhost:3001 (admin/admin)"
    echo "  VictoriaLogs Datasource: http://localhost:8005"
    echo ""
    echo -e "${BOLD}Alerting:${NC}"
    echo "  vmalert UI:           http://localhost:8881"
    echo "  vmalert API:          http://localhost:8881/api/v1/alerts"
    echo ""
    echo -e "${BOLD}Direct Storage Access:${NC}"
    echo "  Node 2 (Storage 1): http://localhost:8002"
    echo "  Node 3 (Storage 2): http://localhost:8003"
    echo "  Load Balancer:        http://localhost:8005"
    echo ""
    echo -e "${BOLD}Pipeline Monitoring:${NC}"
    echo "  Fluent Bit Metrics:   http://localhost:8081/api/v1/metrics"
    echo "  Logstash API:         http://localhost:9601/_node/stats"
    echo "  Kafka:                http://localhost:9094"
}

# Demo commands
show_demo_commands() {
    header "DEMO COMMANDS"
    echo ""
    echo "# Check total logs"
    echo "curl -s 'http://localhost:8005/select/logsql/query?query=*%20%7C%20count()' | jq"
    echo ""
    echo "# Check storage distribution"
    echo "curl -s 'http://localhost:8002/select/logsql/query?query=*%20%7C%20count()'"
    echo "curl -s 'http://localhost:8003/select/logsql/query?query=*%20%7C%20count()'"
    echo ""
    echo "# View recent error logs"
    echo "curl -s 'http://localhost:8005/select/logsql/query?query=level:ERROR%20%7C%20limit%2010' | jq ."
    echo ""
    echo "# Check vmalert alerts"
    echo "curl -s 'http://localhost:8881/api/v1/alerts' | jq '.data.alerts[] | {name: .name, state: .state}'"
}

# Main
main() {
    echo ""
    log "Starting Multi-Node VictoriaLogs Pipeline"
    echo ""
    
    check_ports
    build_log_gen
    start_storage
    start_ingestion
    start_query
    start_orchestrator
    
    log "Waiting for pipeline to stabilize"
    sleep 30
    
    show_status
    show_access
    show_demo_commands
    
    echo ""
    ok "Pipeline startup complete"
    echo ""
}

main