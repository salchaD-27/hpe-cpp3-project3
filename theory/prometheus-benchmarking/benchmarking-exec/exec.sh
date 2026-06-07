# # #!/bin/bash
# # # exec.sh — one-command runner for the multi-node pipeline + cron tier rotation
# # #
# # # Usage:
# # #   ./exec.sh [--purge] [--test] [--cron] [--cron-exec] [--skip-stop]
# # #
# # # Examples:
# # #   ./exec.sh --purge --test --cron --cron-exec
# # #   ./exec.sh --test
# # #   ./exec.sh --purge --cron-exec

# # set -euo pipefail

# # REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# # cd "$REPO_ROOT"

# # PURGE=false
# # RUN_TEST=false
# # RUN_CRON=false
# # RUN_CRON_EXEC=false
# # SKIP_STOP=false

# # while [[ $# -gt 0 ]]; do
# #   case "$1" in
# #     --purge) PURGE=true ;;
# #     --test) RUN_TEST=true ;;
# #     --cron) RUN_CRON=true ;;
# #     --cron-exec) RUN_CRON_EXEC=true ;;
# #     --skip-stop) SKIP_STOP=true ;;
# #     -h|--help)
# #       echo "Usage: $0 [--purge] [--test] [--cron] [--cron-exec] [--skip-stop]"
# #       exit 0
# #       ;;
# #     *)
# #       echo "Unknown arg: $1" >&2
# #       exit 1
# #       ;;
# #   esac
# #   shift
# # done

# # log() { echo -e "[exec.sh] $(date '+%H:%M:%S') $1"; }

# # if [ "$SKIP_STOP" = false ]; then
# #   if [ "$PURGE" = true ]; then
# #     log "Stopping + purging (./stop.sh --purge)"
# #     ./stop.sh --purge
# #   else
# #     log "Stopping (./stop.sh)"
# #     ./stop.sh
# #   fi
# # else
# #   log "Skipping stop (--skip-stop)"
# # fi

# # log "Starting cluster (./start.sh)"
# # ./start.sh

# # # Allow services to stabilize before checks/cron.
# # # start.sh already waits for readiness, but test/cron may need a few extra seconds.
# # log "Waiting 20s for full stabilization"
# # sleep 20

# # if [ "$RUN_TEST" = true ]; then
# #   log "Running verification (./test.sh)"
# #   ./test.sh
# # fi

# # if [ "$RUN_CRON" = true ]; then
# #   log "Installing cron jobs (./scripts/cron/setup_cron.sh)"
# #   ./cron/setup_cron.sh
# # fi

# # if [ "$RUN_CRON_EXEC" = true ]; then
# #   log "Running cron exec scripts (./scripts/cron/cron-exec.sh)"
# #   ./cron/cron-exec.sh
# # fi

# # log "Done"



# #!/bin/bash
# # exec.sh — one-command runner for the multi-node pipeline + cron tier rotation
# #
# # Usage:
# #   ./exec.sh [--purge] [--test] [--cron] [--cron-exec] [--skip-stop]
# #
# # Examples:
# #   ./exec.sh --purge --test --cron --cron-exec
# #   ./exec.sh --test
# #   ./exec.sh --purge --cron-exec

# set -euo pipefail

# REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# cd "$REPO_ROOT"

# PURGE=false
# RUN_TEST=false
# RUN_CRON=false
# RUN_CRON_EXEC=false
# SKIP_STOP=false

# while [[ $# -gt 0 ]]; do
#   case "$1" in
#     --purge) PURGE=true ;;
#     --test) RUN_TEST=true ;;
#     --cron) RUN_CRON=true ;;
#     --cron-exec) RUN_CRON_EXEC=true ;;
#     --skip-stop) SKIP_STOP=true ;;
#     -h|--help)
#       echo "Usage: $0 [--purge] [--test] [--cron] [--cron-exec] [--skip-stop]"
#       exit 0
#       ;;
#     *)
#       echo "Unknown arg: $1" >&2
#       exit 1
#       ;;
#   esac
#   shift
# done

# log() { echo -e "[exec.sh] $(date '+%H:%M:%S') $1"; }

# if [ "$SKIP_STOP" = false ]; then
#   if [ "$PURGE" = true ]; then
#     log "Stopping + purging (./stop.sh --purge)"
#     ./stop.sh --purge
#   else
#     log "Stopping (./stop.sh)"
#     ./stop.sh
#   fi
# else
#   log "Skipping stop (--skip-stop)"
# fi

# log "Starting cluster (./start.sh)"
# ./start.sh

# # Allow services to stabilize before checks/cron.
# log "Waiting 30s for full stabilization"
# sleep 30

# if [ "$RUN_TEST" = true ]; then
#   log "Running verification (./test.sh)"
#   ./test.sh || {
#     log "⚠️ Test had failures, but continuing with cron setup..."
#   }
# fi

# if [ "$RUN_CRON" = true ]; then
#   log "Installing cron jobs (./scripts/cron/setup_cron.sh)"
#   if [ -f "./scripts/cron/setup_cron.sh" ]; then
#     ./scripts/cron/setup_cron.sh
#   else
#     log "⚠️ setup_cron.sh not found, skipping"
#   fi
# fi

# if [ "$RUN_CRON_EXEC" = true ]; then
#   log "Running cron exec scripts (./scripts/cron/cron-exec.sh)"
#   if [ -f "./scripts/cron/cron-exec.sh" ]; then
#     ./scripts/cron/cron-exec.sh
#   else
#     log "⚠️ cron-exec.sh not found, skipping"
#   fi
# fi

# log "Done"


./scripts/stop.sh --purge
rm -rf warm_storage cold_storage
./scripts/start.sh

sleep 10

# 3. Generate new logs
./scripts/benchmark.sh

# 4. Wait 2 minutes, run hot→warm
echo "Waiting 2 minutes for logs to age..."
sleep 120
cd scripts/cron
./rotate_hot_to_warm.sh

# 5. Check warm storage has actual log files
ls -la ../../warm_storage/*/*.gz 2>/dev/null | head -5

# 6. Wait another 2 minutes, run warm→cold
echo "Waiting another 2 minutes..."
sleep 120
./rotate_warm_to_cold.sh

# 7. Check results
./view_tiers.sh