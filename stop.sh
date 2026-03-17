#!/bin/bash

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

log()     { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $*"; }
success() { echo -e "${GREEN}[$(date '+%H:%M:%S')] ✓ $*${NC}"; }
warn()    { echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠ $*${NC}"; }
section() { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${NC}"; \
            echo -e "${BOLD}${CYAN}  $*${NC}"; \
            echo -e "${BOLD}${CYAN}══════════════════════════════════════════${NC}\n"; }

###############################################################################
# OPTIONS
###############################################################################
PURGE=false
if [[ "${1:-}" == "--purge" ]]; then
  PURGE=true
fi

###############################################################################
# STOP
###############################################################################
section "STOPPING PIPELINE"

log "Stopping all containers..."
docker compose down --remove-orphans
success "All containers stopped"

###############################################################################
# PURGE (optional)
###############################################################################
if [ "$PURGE" = true ]; then
  section "PURGING DATA"

  warn "Removing all volumes (Kafka data, Grafana data)..."
  docker compose down -v
  success "Volumes removed"

  warn "Removing log file..."
  rm -f ./0-logs/hpc-cluster.log
  success "Log file removed"

  warn "Removing VictoriaLogs storage..."
  rm -rf ./5-victorialogs/storage-data/*
  success "VictoriaLogs storage cleared"

  success "Full purge complete — next start will begin fresh"
else
  echo -e "
  ${BOLD}Data preserved:${NC}
  • Kafka volume        — kafka-data
  • Grafana volume      — grafana-data
  • VictoriaLogs data   — ./5-victorialogs/storage-data/
  • Log file            — ./0-logs/hpc-cluster.log

  ${YELLOW}To fully wipe all data:${NC}
  ./stop.sh --purge
  "
fi

###############################################################################
# SUMMARY
###############################################################################
section "STATUS"

RUNNING=$(docker compose ps --format "{{.Name}}" 2>/dev/null | wc -l | tr -d ' ')
if [ "$RUNNING" -eq 0 ]; then
  success "All containers down 🛑"
else
  warn "$RUNNING container(s) still running — check: docker compose ps"
fi