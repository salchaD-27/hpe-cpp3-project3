#!/bin/bash

# ============================================================================
# Multi-Node VictoriaLogs Pipeline - Complete Startup Script
# ============================================================================
# This script starts the entire 5-Node distributed log pipeline
# ============================================================================

set -e

# Colors for beautiful output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ============================================================================
# Helper Functions
# ============================================================================
print_banner() {
    echo ""
    echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║${NC}        ${BOLD}MULTI-NODE VICTORIALOGS PIPELINE - ${GREEN}STARTING${NC}                         ${BOLD}${CYAN}║${NC}"
    echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_header() {
    echo ""
    echo -e "${BOLD}${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${MAGENTA}  $1${NC}"
    echo -e "${BOLD}${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_success() {
    echo -e "  ${GREEN}✅${NC} $1"
}

print_error() {
    echo -e "  ${RED}❌${NC} $1"
}

print_info() {
    echo -e "  ${BLUE}▶${NC} $1"
}

print_warning() {
    echo -e "  ${YELLOW}⚠️${NC} $1"
}

print_portal() {
    echo ""
    echo -e "  ${BOLD}${CYAN}🔗${NC} ${BOLD}$1${NC}: ${GREEN}$2${NC}"
}

wait_for() {
    local label=$1
    local cmd=$2
    local retries=${3:-30}
    local delay=${4:-2}
    local i=0
    
    echo -n "  Waiting for $label"
    until eval "$cmd" &>/dev/null; do
        i=$((i+1))
        if [ $i -ge $retries ]; then
            echo ""
            print_error "$label did not become ready"
            return 1
        fi
        echo -n "."
        sleep "$delay"
    done
    echo " ${GREEN}✓${NC}"
    return 0
}

# ============================================================================
# Check Ports
# ============================================================================
check_ports() {
    print_header "PORT VERIFICATION"
    
    PORTS=(8001 8002 8003 8004 8005 8006 8081 8881 3001 9094 9601)
    ALL_FREE=true
    
    for port in "${PORTS[@]}"; do
        if lsof -i :$port -sTCP:LISTEN &>/dev/null; then
            print_error "Port $port is already in use"
            ALL_FREE=false
        else
            print_success "Port $port is available"
        fi
    done
    
    if [ "$ALL_FREE" = false ]; then
        echo ""
        print_error "Please free up the ports above and try again"
        exit 1
    fi
}

# ============================================================================
# Build Images
# ============================================================================
build_images() {
    print_header "BUILDING LOG GENERATOR"
    
    print_info "Building log generator image..."
    cd node-1-ingest/1-log-gen
    docker build -t log-generator:latest . > /dev/null 2>&1
    print_success "Log generator image built"
    cd "$SCRIPT_DIR"
}

# ============================================================================
# Start Storage Nodes
# ============================================================================
start_storage_nodes() {
    print_header "STARTING STORAGE NODES (Node 2 & 3)"
    
    print_info "Starting Node 2 (Storage Node 1)..."
    cd node-2-storage
    docker-compose up -d > /dev/null 2>&1
    print_success "Node 2 started"
    cd "$SCRIPT_DIR"
    
    print_info "Starting Node 3 (Storage Node 2)..."
    cd node-3-storage
    docker-compose up -d > /dev/null 2>&1
    print_success "Node 3 started"
    cd "$SCRIPT_DIR"
    
    wait_for "storage nodes" "curl -s http://localhost:8002/metrics > /dev/null 2>&1 && curl -s http://localhost:8003/metrics > /dev/null 2>&1" 15 2
}

# ============================================================================
# Start Ingestion Node
# ============================================================================
start_ingestion_node() {
    print_header "STARTING INGESTION NODE (Node 1)"
    
    print_info "Starting Node 1 (Ingestion Pipeline)..."
    cd node-1-ingest
    docker-compose up -d > /dev/null 2>&1
    cd "$SCRIPT_DIR"
    
    wait_for "Kafka" "docker exec node-1-kafka /opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092 > /dev/null 2>&1" 30 3
    wait_for "Logstash" "curl -s http://localhost:9601/_node/stats > /dev/null 2>&1" 30 2
    wait_for "vlinsert" "curl -s http://localhost:8001/metrics > /dev/null 2>&1" 15 2
    
    print_success "Node 1 fully operational"
}

# ============================================================================
# Start Query Node
# ============================================================================
start_query_node() {
    print_header "STARTING QUERY NODE (Node 4)"
    
    print_info "Starting Node 4 (Query + Alerting)..."
    cd node-4-query
    docker-compose up -d > /dev/null 2>&1
    cd "$SCRIPT_DIR"
    
    wait_for "vlselect" "curl -s http://localhost:8004/metrics > /dev/null 2>&1" 15 2
    wait_for "Grafana" "curl -s http://localhost:3001/api/health > /dev/null 2>&1" 30 2
    wait_for "vmalert" "curl -s http://localhost:8881/-/healthy > /dev/null 2>&1" 15 2
    
    print_success "Node 4 fully operational"
}

# ============================================================================
# Start Orchestrator Node
# ============================================================================
start_orchestrator_node() {
    print_header "STARTING ORCHESTRATOR NODE (Node 5)"
    
    print_info "Starting Node 5 (Load Balancer + Backup)..."
    cd node-5-orch
    docker-compose up -d > /dev/null 2>&1
    cd "$SCRIPT_DIR"
    
    wait_for "Nginx" "curl -s http://localhost:8005/ > /dev/null 2>&1" 15 2
    wait_for "Backup vlselect" "curl -s http://localhost:8006/metrics > /dev/null 2>&1" 15 2
    
    print_success "Node 5 fully operational"
}

# ============================================================================
# Wait for Pipeline Stabilization
# ============================================================================
wait_for_pipeline() {
    print_header "PIPELINE STABILIZATION"
    
    echo -n "  Waiting for data flow"
    for i in {1..30}; do
        sleep 1
        echo -n "."
    done
    echo " ${GREEN}✓${NC}"
}

# ============================================================================
# Show Pipeline Status
# ============================================================================
show_status() {
    print_header "PIPELINE STATUS"
    
    # Container status
    echo -e "  ${BOLD}📦 Containers:${NC}"
    echo "  ┌─────────────────────────────────────────────────────────────────────────────┐"
    docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | grep -E "node-|NAMES" | sed 's/^/  │ /'
    echo "  └─────────────────────────────────────────────────────────────────────────────┘"
    
    # Storage counts
    echo ""
    echo -e "  ${BOLD}💾 Storage Distribution:${NC}"
    Node2=$(curl -s 'http://localhost:8002/select/logsql/query?query=*%20%7C%20count()' 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('count(*)',0))" 2>/dev/null || echo "0")
    Node3=$(curl -s 'http://localhost:8003/select/logsql/query?query=*%20%7C%20count()' 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('count(*)',0))" 2>/dev/null || echo "0")
    TOTAL=$((Node2 + Node3))
    LB=$(curl -s 'http://localhost:8005/select/logsql/query?query=*%20%7C%20count()' 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('count(*)',0))" 2>/dev/null || echo "0")
    
    echo "  ┌─────────────────────────────────────────────────────────────────────────────┐"
    printf "  │  Node 2 (Storage 1):  %-50s │\n" "$Node2 logs"
    printf "  │  Node 3 (Storage 2):  %-50s │\n" "$Node3 logs"
    printf "  │  Total Storage:         %-50s │\n" "$TOTAL logs"
    printf "  │  Load Balancer:         %-50s │\n" "$LB logs"
    
    if [ "$LB" -eq "$TOTAL" ] && [ "$TOTAL" -gt 0 ]; then
        printf "  │  ${GREEN}✓ Data Consistency:       PASSED${NC}%-35s │\n" ""
    else
        printf "  │  ${RED}✗ Data Consistency:       FAILED${NC}%-35s │\n" ""
    fi
    echo "  └─────────────────────────────────────────────────────────────────────────────┘"
    
    # Pipeline metrics
    echo ""
    echo -e "  ${BOLD}📈 Pipeline Metrics:${NC}"
    FB_RECORDS=$(curl -s http://localhost:8081/api/v1/metrics 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('input',{}).get('tail.0',{}).get('records',0))" 2>/dev/null || echo "0")
    LS_OUT=$(curl -s http://localhost:9601/_node/stats 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('pipelines',{}).get('main',{}).get('events',{}).get('out',0))" 2>/dev/null || echo "0")
    
    echo "  ┌─────────────────────────────────────────────────────────────────────────────┐"
    printf "  │  Fluent Bit Records:   %-50s │\n" "$FB_RECORDS"
    printf "  │  Logstash Events Out:   %-50s │\n" "$LS_OUT"
    printf "  │  Logstash Throughput:   %-50s │\n" "$(curl -s http://localhost:9601/_node/stats 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('pipelines',{}).get('main',{}).get('flow',{}).get('output_throughput',{}).get('current',0))" 2>/dev/null || echo "0") events/sec"
    echo "  └─────────────────────────────────────────────────────────────────────────────┘"
}

# ============================================================================
# Show Access Portal
# ============================================================================
show_portal() {
    print_header "ACCESS PORTAL"
    
    echo -e "  ${BOLD}${GREEN}🎯 READY FOR DEMO!${NC}"
    echo ""
    echo -e "  ${BOLD}📊 Grafana Dashboard:${NC}"
    echo "  ┌─────────────────────────────────────────────────────────────────────────────┐"
    print_portal "Grafana UI" "http://localhost:3001 (admin/admin)"
    print_portal "VictoriaLogs Datasource" "http://localhost:8005"
    echo "  └─────────────────────────────────────────────────────────────────────────────┘"
    
    echo ""
    echo -e "  ${BOLD}🔔 Alerting:${NC}"
    echo "  ┌─────────────────────────────────────────────────────────────────────────────┐"
    print_portal "vmalert UI" "http://localhost:8881"
    print_portal "vmalert API" "http://localhost:8881/api/v1/alerts"
    echo "  └─────────────────────────────────────────────────────────────────────────────┘"
    
    echo ""
    echo -e "  ${BOLD}💾 Direct Storage Access:${NC}"
    echo "  ┌─────────────────────────────────────────────────────────────────────────────┐"
    print_portal "Node 2 (Storage 1)" "http://localhost:8002"
    print_portal "Node 3 (Storage 2)" "http://localhost:8003"
    print_portal "Load Balancer (Query)" "http://localhost:8005"
    echo "  └─────────────────────────────────────────────────────────────────────────────┘"
    
    echo ""
    echo -e "  ${BOLD}🔧 Pipeline Monitoring:${NC}"
    echo "  ┌─────────────────────────────────────────────────────────────────────────────┐"
    print_portal "Fluent Bit Metrics" "http://localhost:8081/api/v1/metrics"
    print_portal "Logstash API" "http://localhost:9601/_node/stats"
    print_portal "Kafka" "http://localhost:9094"
    echo "  └─────────────────────────────────────────────────────────────────────────────┘"
    
    echo ""
    echo -e "  ${BOLD}${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "  ${BOLD}${GREEN}  🚀 Pipeline is fully operational!${NC}"
    echo -e "  ${BOLD}${CYAN}════════════════════════════════════════════════════════════════════════════════${NC}"
}

# ============================================================================
# Demo Commands
# ============================================================================
show_demo_commands() {
    print_header "DEMO COMMANDS"
    
    echo ""
    echo -e "  ${BOLD}${YELLOW}Quick Test Commands (copy-paste ready):${NC}"
    echo ""
    echo -e "  ${BOLD}# Check total logs${NC}"
    echo -e "  ${GREEN}curl -s 'http://localhost:8005/select/logsql/query?query=*%20%7C%20count()' | jq${NC}"
    echo ""
    echo -e "  ${BOLD}# Check storage distribution${NC}"
    echo -e "  ${GREEN}curl -s 'http://localhost:8002/select/logsql/query?query=*%20%7C%20count()'${NC}"
    echo -e "  ${GREEN}curl -s 'http://localhost:8003/select/logsql/query?query=*%20%7C%20count()'${NC}"
    echo ""
    echo -e "  ${BOLD}# View recent error logs${NC}"
    echo -e "  ${GREEN}curl -s 'http://localhost:8005/select/logsql/query?query=level:ERROR%20%7C%20limit%2010' | jq .${NC}"
    echo ""
    echo -e "  ${BOLD}# Check vmalert alerts${NC}"
    echo -e  "${GREEN}curl -s 'http://localhost:8881/api/v1/alerts' | jq '.data.alerts[] | {name: .name, state: .state}'${NC}"
}

# ============================================================================
# Main Execution
# ============================================================================
main() {
    print_banner
    
    check_ports
    build_images
    start_storage_nodes
    start_ingestion_node
    start_query_node
    start_orchestrator_node
    wait_for_pipeline
    show_status
    show_portal
    show_demo_commands
    
    echo ""
    echo -e "${GREEN}${BOLD}✨ Pipeline startup complete!${NC}"
    echo ""
}

# Run main
main