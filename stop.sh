#!/bin/bash
# =============================================================================
# stop.sh — 5-Node HPC Log Pipeline
# Stops in reverse order of startup. --purge wipes all data.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()    { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"; }
ok()     { echo -e "${GREEN}[OK]${NC} $1"; }
warn()   { echo -e "${YELLOW}[WARN]${NC} $1"; }
header() { echo -e "\n${BOLD}${CYAN}=== $1 ===${NC}"; }

PURGE=false
[[ "$1" == "--purge" || "$1" == "-p" ]] && PURGE=true

stop_node() {
    local dir=$1 name=$2
    if [ -f "$dir/docker-compose.yml" ]; then
        log "Stopping $name"
        (cd "$dir" && docker compose down) >/dev/null 2>&1
        ok "$name stopped"
    else
        warn "$name config not found at $dir"
    fi
}

purge_data() {
    header "PURGING DATA"
    warn "Deleting ALL pipeline data — this cannot be undone!"

    log "Removing named volumes"
    docker volume rm -f \
        "$(docker volume ls -q | grep -E 'kafka-data|grafana-data|victoriametrics-data|logstash-dlq|generated-logs' || true)" \
        2>/dev/null || true
    ok "Volumes removed"

    log "Cleaning generated log files"
    rm -rf node-1-pipeline/1-simulator/logs-generated/*.jsonl 2>/dev/null || true
    ok "Generated logs cleaned"

    log "Cleaning VictoriaLogs storage (bind-mounts)"
    rm -rf node-3-vlstorage/storage/* 2>/dev/null || true
    rm -rf node-4-vlstorage/storage/* 2>/dev/null || true
    # Recreate directories so vlstorage can mount them
    mkdir -p node-3-vlstorage/storage node-4-vlstorage/storage
    ok "VictoriaLogs storage cleaned"
}

cleanup_network() {
    header "NETWORK CLEANUP"
    if docker network inspect multi-node-net >/dev/null 2>&1; then
        docker network rm multi-node-net >/dev/null 2>&1 && ok "multi-node-net removed" \
            || warn "Could not remove multi-node-net (containers still attached?)"
    else
        ok "multi-node-net already gone"
    fi
}

main() {
    echo ""
    log "Stopping 5-Node HPC Log Pipeline"
    [ "$PURGE" = true ] && warn "PURGE MODE — all data will be deleted!"
    echo ""

    header "STOPPING NODES (reverse order)"
    # Stop in reverse startup order
    stop_node "node-1-pipeline" "Pipeline node (Node 1)"
    stop_node "node-5-vlselect" "Query node (Node 5)"
    stop_node "node-2-vlinsert" "Write gateway (Node 2)"
    stop_node "node-4-vlstorage" "Storage node 2 (Node 4)"
    stop_node "node-3-vlstorage" "Storage node 1 (Node 3)"

    [ "$PURGE" = true ] && purge_data

    cleanup_network

    echo ""
    ok "Pipeline stopped"
    [ "$PURGE" = true ] && ok "Full purge complete — ready for a fresh start"
    [ "$PURGE" = false ] && warn "Data preserved. To wipe all data: ./stop.sh --purge"
    echo ""
}

main
