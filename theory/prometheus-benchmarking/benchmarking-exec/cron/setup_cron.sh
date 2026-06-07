# #!/bin/bash
# # =============================================================================
# # Setup Cron Jobs for Storage Tier Rotation
# # =============================================================================

# SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# # Make scripts executable
# chmod +x "$SCRIPT_DIR/rotate_hot_to_warm.sh"
# chmod +x "$SCRIPT_DIR/rotate_warm_to_cold.sh"
# chmod +x "$SCRIPT_DIR/view_tiers.sh"

# # Create crontab entries
# (crontab -l 2>/dev/null; echo "# Hot to Warm rotation - Daily at 2 AM") | crontab -
# (crontab -l 2>/dev/null; echo "0 2 * * * $SCRIPT_DIR/rotate_hot_to_warm.sh >> $REPO_ROOT/logs/storage_rotation.log 2>&1") | crontab -

# (crontab -l 2>/dev/null; echo "# Warm to Cold rotation - Weekly on Sunday at 3 AM") | crontab -
# (crontab -l 2>/dev/null; echo "0 3 * * 0 $SCRIPT_DIR/rotate_warm_to_cold.sh >> $REPO_ROOT/logs/storage_rotation.log 2>&1") | crontab -

# echo "Cron jobs installed:"
# echo "   - Daily 2 AM: Hot → Warm rotation"
# echo "   - Weekly Sunday 3 AM: Warm → Cold rotation"
# echo ""
# echo "View tier status: $SCRIPT_DIR/view_tiers.sh"
# echo "Logs: $REPO_ROOT/logs/storage_rotation.log"







# #!/bin/bash
# # =============================================================================
# # TEST VERSION: Warm to Cold Tier Rotation (4 MINUTES)
# # Converts logs older than 4 minutes to Prometheus metrics and archives
# # For testing purposes only - use with 4 minute threshold
# # =============================================================================

# SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# cd "$REPO_ROOT"

# # Colors
# GREEN='\033[0;32m'
# YELLOW='\033[1;33m'
# BLUE='\033[0;34m'
# RED='\033[0;31m'
# NC='\033[0m'

# log() { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
# ok() { echo -e "${GREEN}[OK]${NC} $1"; }
# warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
# error() { echo -e "${RED}[ERROR]${NC} $1"; }

# # Configuration
# WARM_STORAGE_DIR="$REPO_ROOT/warm_storage"
# COLD_STORAGE_DIR="$REPO_ROOT/cold_storage/metrics"
# PROMETHEUS_PUSHGATEWAY="http://localhost:9091/metrics/job/log_archive"

# # TEST CONFIGURATION: 4 MINUTES = 240 seconds
# # Using -mmin (minutes) instead of -mtime (days) for fine-grained control
# MINUTES_OLD=4

# # Create cold storage directory
# mkdir -p "$COLD_STORAGE_DIR"

# log "=========================================="
# log "TEST MODE: Warm → Cold rotation (converting logs older than ${MINUTES_OLD} MINUTES to metrics)"
# log "=========================================="

# # Keep track of totals
# total_archived=0
# total_metrics=0

# # Process each warm storage directory
# find "$WARM_STORAGE_DIR" -type d -name "node-*_*" -mmin +${MINUTES_OLD} 2>/dev/null | while read warm_dir; do
#     log "Processing warm directory: $(basename "$warm_dir")"
    
#     # Extract metrics from compressed logs older than MINUTES_OLD
#     find "$warm_dir" -name "*.gz" -mmin +${MINUTES_OLD} | while read gz_file; do
#         file_size=$(stat -f "%z" "$gz_file" 2>/dev/null || stat --format "%s" "$gz_file" 2>/dev/null)
#         file_size_mb=$(echo "scale=2; $file_size / 1024 / 1024" | bc)
        
#         log "  Converting: $(basename "$gz_file") (${file_size_mb} MB compressed)"
        
#         # Decompress and convert to Prometheus metrics
#         metrics_sent=$(gunzip -c "$gz_file" | python3 << 'PYTHON_EOF'
# import json
# import sys
# import requests
# from datetime import datetime

# prometheus_url = "http://localhost:9091/metrics/job/log_archive"
# metrics_sent = 0
# metrics_list = []

# for line in sys.stdin:
#     try:
#         log = json.loads(line)
#         timestamp = int(datetime.now().timestamp() * 1000)
#         level = log.get('level', 'INFO')
#         service = log.get('service_name', 'unknown')
#         host = log.get('host_name', 'unknown')
        
#         # Create Prometheus metrics
#         metrics = [
#             f'hpc_cold_logs_total{{level="{level}",service="{service}",host="{host}"}} 1 {timestamp}',
#             f'hpc_cold_log_bytes{{service="{service}"}} {len(line)} {timestamp}'
#         ]
        
#         if level == 'ERROR':
#             metrics.append(f'hpc_cold_errors_total{{service="{service}"}} 1 {timestamp}')
        
#         # Collect metrics
#         metrics_list.extend(metrics)
        
#         # Send in batches of 100 to avoid overwhelming
#         if len(metrics_list) >= 100:
#             for metric in metrics_list:
#                 try:
#                     requests.post(prometheus_url, data=metric, timeout=2)
#                     metrics_sent += 1
#                 except:
#                     pass
#             metrics_list = []
            
#     except Exception as e:
#         pass

# # Send remaining metrics
# for metric in metrics_list:
#     try:
#         requests.post(prometheus_url, data=metric, timeout=2)
#         metrics_sent += 1
#     except:
#         pass

# print(metrics_sent)
# PYTHON_EOF
# )
        
#         total_metrics=$((total_metrics + metrics_sent))
        
#         # Log conversion results
#         if [ "$metrics_sent" -gt 0 ]; then
#             ok "    Converted: $metrics_sent metrics sent to Prometheus Pushgateway"
#         else
#             warn "    No metrics extracted from $(basename "$gz_file")"
#         fi
        
#         # Get original size before moving
#         original_size=$(stat -f "%z" "$gz_file" 2>/dev/null || stat --format "%s" "$gz_file" 2>/dev/null)
        
#         # Move to cold storage archive
#         mv "$gz_file" "$COLD_STORAGE_DIR/"
#         total_archived=$((total_archived + 1))
#         ok "    Archived: $(basename "$gz_file")"
        
#         # Show storage savings
#         if [ -n "$original_size" ]; then
#             # After conversion to metrics, the data is in Prometheus TSDB, not in the archived file
#             # The archived gz file is just a backup
#             ok "    Original size: $(echo "scale=2; $original_size / 1024 / 1024" | bc) MB (archived)"
#         fi
#     done
    
#     # Remove empty directory if it exists
#     rmdir "$warm_dir" 2>/dev/null && log "  Removed empty directory: $(basename "$warm_dir")"
# done

# # Show cold storage stats
# cold_count=$(find "$COLD_STORAGE_DIR" -type f -name "*.gz" 2>/dev/null | wc -l)
# cold_size=$(du -sh "$COLD_STORAGE_DIR" 2>/dev/null | cut -f1)

# # Check Prometheus for metrics
# log "Checking Prometheus Pushgateway for cold metrics..."
# prom_metrics=$(curl -s "http://localhost:9091/metrics" 2>/dev/null | grep -c "hpc_cold" || echo "0")

# log "=========================================="
# log "Warm → Cold rotation complete"
# ok "Summary:"
# ok "  Files archived to cold storage: $cold_count"
# ok "  Cold storage total size: $cold_size"
# ok "  Metrics sent to Prometheus: $total_metrics"
# ok "  Metrics visible in Pushgateway: $prom_metrics"
# log "=========================================="

# # Verify Prometheus metrics
# if [ "$prom_metrics" -gt 0 ]; then
#     ok "✅ Cold metrics are available in Prometheus!"
#     echo ""
#     log "Sample cold metrics from Pushgateway:"
#     curl -s "http://localhost:9091/metrics" 2>/dev/null | grep "hpc_cold" | head -5 | while read line; do
#         echo "    $line"
#     done
# else
#     warn "No cold metrics found in Pushgateway. Check if pushgateway is running:"
#     echo "    docker ps | grep pushgateway"
# fi





#!/bin/bash
# =============================================================================
# TEST VERSION: Setup Cron Jobs for Storage Tier Rotation
# Runs hot→warm every 2 minutes, warm→cold every 4 minutes
# FOR TESTING PURPOSES ONLY
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
ok() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Create logs directory
mkdir -p "$REPO_ROOT/logs"

# Make scripts executable
chmod +x "$SCRIPT_DIR/rotate_hot_to_warm.sh"
chmod +x "$SCRIPT_DIR/rotate_warm_to_cold.sh"
chmod +x "$SCRIPT_DIR/view_tiers.sh"

# Backup existing crontab
crontab -l > /tmp/crontab_backup_$(date +%Y%m%d_%H%M%S).txt 2>/dev/null
ok "Existing crontab backed up"

# Remove old entries if they exist
crontab -l 2>/dev/null | grep -v "rotate_hot_to_warm" | grep -v "rotate_warm_to_cold" | crontab - 2>/dev/null || true

# =============================================================================
# TEST CONFIGURATION: Every 2 minutes for hot→warm
# =============================================================================
log "Installing TEST cron jobs with 2-minute and 4-minute intervals..."

# Hot to Warm: Every 2 minutes (for testing)
(crontab -l 2>/dev/null; echo "# TEST: Hot to Warm rotation - Every 2 minutes") | crontab -
(crontab -l 2>/dev/null; echo "*/2 * * * * $SCRIPT_DIR/rotate_hot_to_warm.sh >> $REPO_ROOT/logs/storage_rotation.log 2>&1") | crontab -
ok "Hot → Warm: Every 2 minutes"

# Warm to Cold: Every 4 minutes (for testing)
(crontab -l 2>/dev/null; echo "# TEST: Warm to Cold rotation - Every 4 minutes") | crontab -
(crontab -l 2>/dev/null; echo "*/4 * * * * $SCRIPT_DIR/rotate_warm_to_cold.sh >> $REPO_ROOT/logs/storage_rotation.log 2>&1") | crontab -
ok "Warm → Cold: Every 4 minutes"

# =============================================================================
# Optional: Add a status check every minute (for monitoring)
# =============================================================================
(crontab -l 2>/dev/null; echo "# TEST: Storage tier status check - Every 5 minutes") | crontab -
(crontab -l 2>/dev/null; echo "*/5 * * * * $SCRIPT_DIR/view_tiers.sh >> $REPO_ROOT/logs/tier_status.log 2>&1") | crontab -
ok "Status check: Every 5 minutes"

echo ""
log "=========================================="
log "TEST CRON JOBS INSTALLED"
log "=========================================="
echo ""
echo "┌─────────────────────────────────────────────────────────────────────────────┐"
echo "│                          TEST SCHEDULE                                      │"
echo "├─────────────────────────────────────────────────────────────────────────────┤"
echo "│                                                                             │"
echo "│   */2 * * * *    → Hot → Warm rotation (every 2 minutes)                   │"
echo "│   */4 * * * *    → Warm → Cold rotation (every 4 minutes)                  │"
echo "│   */5 * * * *    → Storage tier status (every 5 minutes)                   │"
echo "│                                                                             │"
echo "└─────────────────────────────────────────────────────────────────────────────┘"
echo ""
echo "📁 Log files:"
echo "   Storage rotation log: $REPO_ROOT/logs/storage_rotation.log"
echo "   Tier status log:      $REPO_ROOT/logs/tier_status.log"
echo ""
echo "📊 View commands:"
echo "   Watch rotation log:   tail -f $REPO_ROOT/logs/storage_rotation.log"
echo "   View tier status:     $SCRIPT_DIR/view_tiers.sh"
echo "   List cron jobs:       crontab -l"
echo ""
echo "⚠️  IMPORTANT: These are TEST cron jobs with very short intervals!"
echo "   To revert to production settings, run: $SCRIPT_DIR/setup_cron_production.sh"
echo ""

# Optional: Show current crontab
log "Current crontab entries:"
echo "----------------------------------------"
crontab -l | grep -E "rotate_|view_tiers" || echo "  No rotation jobs found"
echo "----------------------------------------"

# =============================================================================
# Create production restore script
# =============================================================================
cat > "$SCRIPT_DIR/setup_cron_production.sh" << 'PROD_EOF'
#!/bin/bash
# =============================================================================
# PRODUCTION: Setup Cron Jobs for Storage Tier Rotation
# Runs daily at 2 AM and weekly on Sunday at 3 AM
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

mkdir -p "$REPO_ROOT/logs"

# Remove test entries
crontab -l 2>/dev/null | grep -v "rotate_hot_to_warm" | grep -v "rotate_warm_to_cold" | crontab - 2>/dev/null || true

# Install production schedules
(crontab -l 2>/dev/null; echo "# PRODUCTION: Hot to Warm rotation - Daily at 2 AM") | crontab -
(crontab -l 2>/dev/null; echo "0 2 * * * $SCRIPT_DIR/rotate_hot_to_warm.sh >> $REPO_ROOT/logs/storage_rotation.log 2>&1") | crontab -

(crontab -l 2>/dev/null; echo "# PRODUCTION: Warm to Cold rotation - Weekly Sunday at 3 AM") | crontab -
(crontab -l 2>/dev/null; echo "0 3 * * 0 $SCRIPT_DIR/rotate_warm_to_cold.sh >> $REPO_ROOT/logs/storage_rotation.log 2>&1") | crontab -

echo "Production cron jobs installed:"
echo "   - Daily 2 AM: Hot → Warm rotation"
echo "   - Weekly Sunday 3 AM: Warm → Cold rotation"
PROD_EOF

chmod +x "$SCRIPT_DIR/setup_cron_production.sh"
ok "Production restore script created: $SCRIPT_DIR/setup_cron_production.sh"

# =============================================================================
# Create monitoring script
# =============================================================================
cat > "$SCRIPT_DIR/monitor_tiers.sh" << 'MONITOR_EOF'
#!/bin/bash
# =============================================================================
# Monitor storage tier status in real-time
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

while true; do
    clear
    echo "════════════════════════════════════════════════════════════════"
    echo "  STORAGE TIER MONITOR - $(date '+%Y-%m-%d %H:%M:%S')"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    
    # Hot tier stats
    echo "🔥 HOT TIER (Active Storage)"
    for port in 8002 8003 8005 8006; do
        count=$(curl -s "http://localhost:$port/select/logsql/query?query=*%20%7C%20count()" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(list(d.values())[0] if d else 0)" 2>/dev/null || echo "0")
        echo "   Port $port: $count logs"
    done
    
    # Warm tier stats
    echo ""
    echo "🌡️ WARM TIER (Compressed Storage)"
    if [ -d "$REPO_ROOT/warm_storage" ]; then
        warm_files=$(find "$REPO_ROOT/warm_storage" -type f -name "*.gz" 2>/dev/null | wc -l)
        warm_size=$(du -sh "$REPO_ROOT/warm_storage" 2>/dev/null | cut -f1)
        echo "   Files: $warm_files"
        echo "   Size: $warm_size"
    else
        echo "   Directory not found"
    fi
    
    # Cold tier stats
    echo ""
    echo "❄️ COLD TIER (Prometheus Metrics)"
    if [ -d "$REPO_ROOT/cold_storage/metrics" ]; then
        cold_files=$(find "$REPO_ROOT/cold_storage/metrics" -type f -name "*.gz" 2>/dev/null | wc -l)
        cold_size=$(du -sh "$REPO_ROOT/cold_storage/metrics" 2>/dev/null | cut -f1)
        echo "   Archived files: $cold_files"
        echo "   Archive size: $cold_size"
    else
        echo "   Directory not found"
    fi
    
    # Prometheus metrics
    echo ""
    echo "📈 PROMETHEUS COLD METRICS"
    metric_count=$(curl -s "http://localhost:9091/metrics" 2>/dev/null | grep -c "hpc_cold" || echo "0")
    echo "   Metrics in Pushgateway: $metric_count"
    
    echo ""
    echo "Press Ctrl+C to exit | Refreshing every 10 seconds..."
    sleep 10
done
MONITOR_EOF

chmod +x "$SCRIPT_DIR/monitor_tiers.sh"
ok "Monitor script created: $SCRIPT_DIR/monitor_tiers.sh"

log "=========================================="
log "TEST SETUP COMPLETE"
log "=========================================="
echo ""
echo "🚀 Quick Start:"
echo "   1. Start cluster:    ./scripts/start.sh"
echo "   2. Generate logs:    ./scripts/benchmark.sh"
echo "   3. Monitor tiers:    ./scripts/cron/monitor_tiers.sh"
echo "   4. Watch rotation:   tail -f logs/storage_rotation.log"
echo ""
echo "🛑 To stop testing and restore production:"
echo "   ./scripts/cron/setup_cron_production.sh"
echo ""