#!/bin/bash

# ============================================================================
# Multi-Node VictoriaLogs Pipeline - Complete Shutdown Script
# ============================================================================
# This script stops all containers and optionally purges all data
# ============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# Parse arguments
PURGE=false
if [[ "$1" == "--purge" ]] || [[ "$1" == "-p" ]]; then
    PURGE=true
fi

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Helper functions
print_banner() {
    echo ""
    echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║${NC}        ${BOLD}MULTI-NODE VICTORIALOGS PIPELINE - ${RED}STOPPING${NC}                       ${BOLD}${CYAN}║${NC}"
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

# ============================================================================
# Stop Orchestrator Node
# ============================================================================
stop_orchestrator() {
    print_info "Stopping Node 5 (Orchestrator)..."
    if [ -f "node-5-orch/docker-compose.yml" ]; then
        cd node-5-orch && docker-compose down 2>/dev/null && cd ..
        print_success "Node 5 stopped"
    else
        print_warning "Node 5 not found"
    fi
}

# ============================================================================
# Stop Query Node
# ============================================================================
stop_query() {
    print_info "Stopping Node 4 (Query + Alerting)..."
    if [ -f "node-4-query/docker-compose.yml" ]; then
        cd node-4-query && docker-compose down 2>/dev/null && cd ..
        print_success "Node 4 stopped"
    else
        print_warning "Node 4 not found"
    fi
}

# ============================================================================
# Stop Ingestion Node
# ============================================================================
stop_ingestion() {
    print_info "Stopping Node 1 (Ingestion)..."
    if [ -f "node-1-ingest/docker-compose.yml" ]; then
        cd node-1-ingest && docker-compose down 2>/dev/null && cd ..
        print_success "Node 1 stopped"
    else
        print_warning "Node 1 not found"
    fi
}

# ============================================================================
# Stop Storage Nodes
# ============================================================================
stop_storage() {
    print_info "Stopping Node 2 (Storage Node 1)..."
    if [ -f "node-2-storage/docker-compose.yml" ]; then
        cd node-2-storage && docker-compose down 2>/dev/null && cd ..
        print_success "Node 2 stopped"
    else
        print_warning "Node 2 not found"
    fi
    
    print_info "Stopping Node 3 (Storage Node 2)..."
    if [ -f "node-3-storage/docker-compose.yml" ]; then
        cd node-3-storage && docker-compose down 2>/dev/null && cd ..
        print_success "Node 3 stopped"
    else
        print_warning "Node 3 not found"
    fi
}

# ============================================================================
# Force Remove All Containers
# ============================================================================
force_cleanup() {
    print_header "FORCE CLEANUP"
    
    print_info "Removing all node containers..."
    docker ps -a | grep -E "node-[1-5]" | awk '{print $1}' | xargs -r docker rm -f 2>/dev/null
    print_success "All node containers removed"
    
    print_info "Removing networks..."
    docker network ls | grep -E "node-[1-5]" | awk '{print $2}' | xargs -r docker network rm 2>/dev/null
    print_success "Networks removed"
}

# ============================================================================
# Purge Data (Optional)
# ============================================================================
purge_data() {
    print_header "PURGING DATA"
    
    print_warning "This will delete ALL pipeline data!"
    
    print_info "Removing volumes..."
    docker volume rm -f $(docker volume ls -q | grep -E "kafka-data|grafana-data") 2>/dev/null
    print_success "Volumes removed"
    
    print_info "Cleaning log files..."
    rm -rf node-1-ingest/1-log-gen/logs-generated/*.jsonl 2>/dev/null
    rm -rf node-2-storage/storage/* 2>/dev/null
    rm -rf node-3-storage/storage/* 2>/dev/null
    print_success "Log files cleaned"
    
    print_info "Cleaning VictoriaLogs storage..."
    rm -rf node-2-storage/storage 2>/dev/null
    rm -rf node-3-storage/storage 2>/dev/null
    mkdir -p node-2-storage/storage node-3-storage/storage
    print_success "VictoriaLogs storage cleaned"
    
    print_info "Cleaning Logstash DLQ..."
    rm -rf node-1-ingest/4-logstash/dlq 2>/dev/null
    print_success "DLQ cleaned"
}

# ============================================================================
# Show Final Status
# ============================================================================
show_final_status() {
    print_header "FINAL STATUS"
    
    REMAINING=$(docker ps -a | grep -c "node-" 2>/dev/null || echo "0")
    
    if [ "$REMAINING" -eq 0 ]; then
        echo -e "  ${GREEN}✅ All containers stopped${NC}"
    else
        echo -e "  ${YELLOW}⚠️ $REMAINING containers still running${NC}"
        docker ps | grep -E "node-" 2>/dev/null | sed 's/^/    /'
    fi
    
    echo ""
    if [ "$PURGE" = true ]; then
        echo -e "  ${GREEN}✅ Full purge completed - Fresh start ready${NC}"
    else
        echo -e "  ${BLUE}📦 Data preserved${NC}"
        echo -e "  ${YELLOW}💡 To wipe all data: ${BOLD}./stop.sh --purge${NC}"
    fi
}

# ============================================================================
# Main Execution
# ============================================================================
main() {
    print_banner
    
    if [ "$PURGE" = true ]; then
        print_warning "PURGE MODE ENABLED - All data will be deleted!"
        echo ""
    fi
    
    print_header "STOPPING PIPELINE"
    
    # Stop in reverse order
    stop_orchestrator
    stop_query
    stop_ingestion
    stop_storage
    
    # Force cleanup
    force_cleanup
    
    # Purge if requested
    if [ "$PURGE" = true ]; then
        purge_data
    fi
    
    show_final_status
    
    echo ""
    echo -e "${GREEN}${BOLD}✨ Pipeline stopped successfully!${NC}"
    echo ""
}

# Run main
main