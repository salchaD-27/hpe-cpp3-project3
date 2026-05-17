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

log() { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"; }
ok() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
header() { echo -e "\n${BOLD}${CYAN}=== $1 ===${NC}"; }

PURGE=false
[[ "$1" == "--purge" || "$1" == "-p" ]] && PURGE=true

stop_compose() {
    local dir=$1 name=$2
    if [ -f "$dir/docker-compose.yml" ]; then
        log "Stopping $name"
        cd "$dir" && docker-compose down 2>/dev/null && cd ..
        ok "$name stopped"
    else
        warn "$name config not found"
    fi
}

force_cleanup() {
    header "FORCE CLEANUP"
    log "Removing all node containers"
    docker ps -a | grep -E "node-[1-5]" | awk '{print $1}' | xargs -r docker rm -f 2>/dev/null
    ok "All node containers removed"
    
    log "Removing networks"
    docker network ls | grep -E "node-[1-5]" | awk '{print $2}' | xargs -r docker network rm 2>/dev/null
    ok "Networks removed"
}

purge_data() {
    header "PURGING DATA"
    warn "This will delete ALL pipeline data!"
    
    log "Removing volumes"
    docker volume rm -f $(docker volume ls -q | grep -E "kafka-data|grafana-data") 2>/dev/null
    ok "Volumes removed"
    
    log "Cleaning log files"
    rm -rf node-1-ingest/1-log-gen/logs-generated/*.jsonl 2>/dev/null
    rm -rf node-2-storage/storage/* 2>/dev/null
    rm -rf node-3-storage/storage/* 2>/dev/null
    ok "Log files cleaned"
    
    log "Cleaning VictoriaLogs storage"
    rm -rf node-2-storage/storage 2>/dev/null
    rm -rf node-3-storage/storage 2>/dev/null
    mkdir -p node-2-storage/storage node-3-storage/storage
    ok "VictoriaLogs storage cleaned"
    
    log "Cleaning Logstash DLQ"
    rm -rf node-1-ingest/4-logstash/dlq 2>/dev/null
    ok "DLQ cleaned"
}

show_final_status() {
    header "FINAL STATUS"
    
    REMAINING=$(docker ps -a 2>/dev/null | grep -c "node-" || true)
    if [ "${REMAINING:-0}" -eq 0 ]; then
        ok "All containers stopped"
    else
        warn "$REMAINING containers still running"
        docker ps | grep -E "node-" 2>/dev/null
    fi
    
    echo ""
    if [ "$PURGE" = true ]; then
        ok "Full purge completed - Fresh start ready"
    else
        warn "Data preserved. To wipe all data: ./stop.sh --purge"
    fi
}

main() {
    echo ""
    log "Stopping Multi-Node VictoriaLogs Pipeline"
    [ "$PURGE" = true ] && warn "PURGE MODE ENABLED - All data will be deleted!"
    echo ""
    
    header "STOPPING PIPELINE"
    
    # Stop in reverse order
    stop_compose "node-5-orch" "Orchestrator node (Node 5)"
    stop_compose "node-4-query" "Query node (Node 4)"
    stop_compose "node-1-ingest" "Ingestion node (Node 1)"
    stop_compose "node-2-storage" "Storage node 1 (Node 2)"
    stop_compose "node-3-storage" "Storage node 2 (Node 3)"

    force_cleanup

    if [ "$PURGE" = true ]; then
        purge_data
    fi
    
    show_final_status
    
    echo ""
    ok "Pipeline stopped"
    echo ""
}

main