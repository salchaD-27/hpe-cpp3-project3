# #!/bin/bash
# # =============================================================================
# # Rotate logs from warm to cold tier (runs weekly at 3 AM)
# # Converts logs older than 30 days to Prometheus metrics and archives
# # =============================================================================

# WARM_DIR="/var/lib/victoriametrics-warm"
# COLD_DIR="/var/lib/prometheus-cold"
# PROMETHEUS_URL="http://node-3-pushgateway:9091/metrics/job/log_archive"
# DAYS_OLD=30

# echo "[$(date)] Starting warm to cold conversion..."

# # Create cold directory
# mkdir -p "$COLD_DIR"

# find "$WARM_DIR" -type f -name "*.jsonl.gz" -mtime +$DAYS_OLD 2>/dev/null | while read file; do
#     echo "  Processing: $(basename "$file")"
    
#     # Decompress and convert to Prometheus metrics
#     gunzip -c "$file" | python3 << 'PYTHON_EOF'
# import json
# import sys
# import requests
# from datetime import datetime

# prometheus_url = "http://node-3-pushgateway:9091/metrics/job/log_archive"
# metrics_sent = 0

# for line in sys.stdin:
#     try:
#         log = json.loads(line)
#         timestamp = int(datetime.now().timestamp() * 1000)
#         level = log.get("level", "INFO")
#         service = log.get("service_name", "unknown")
        
#         # Create Prometheus metrics
#         metrics = [
#             f'hpc_archived_logs_total{{level="{level}",service="{service}"}} 1 {timestamp}',
#             f'hpc_archived_log_bytes{{service="{service}"}} {len(line)} {timestamp}'
#         ]
        
#         if level == "ERROR":
#             metrics.append(f'hpc_archived_errors_total{{service="{service}"}} 1 {timestamp}')
        
#         # Send to Pushgateway
#         for metric in metrics:
#             try:
#                 requests.post(prometheus_url, data=metric, timeout=2)
#                 metrics_sent += 1
#             except:
#                 pass
#     except:
#         pass

# print(f"    Sent {metrics_sent} metrics to Prometheus")
# PYTHON_EOF
    
#     # Move to cold storage archive
#     mv "$file" "$COLD_DIR/"
#     echo "  Archived: $(basename "$file")"
# done

# echo "[$(date)] Warm to cold conversion complete"

# # Show stats
# COLD_COUNT=$(find "$COLD_DIR" -type f -name "*.gz" 2>/dev/null | wc -l)
# COLD_SIZE=$(du -sh "$COLD_DIR" 2>/dev/null | cut -f1)
# echo "  Cold storage: $COLD_COUNT files, $COLD_SIZE"


#!/bin/bash
# =============================================================================
# Warm to Cold Tier Rotation
# Converts logs older than 30 days to Prometheus metrics and archives
# Runs weekly on Sunday at 3 AM
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
ok() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Configuration
WARM_STORAGE_DIR="$REPO_ROOT/warm_storage"
COLD_STORAGE_DIR="$REPO_ROOT/cold_storage/metrics"
PROMETHEUS_PUSHGATEWAY="http://localhost:9091/metrics/job/log_archive"
DAYS_OLD=30

# Create cold storage directory
mkdir -p "$COLD_STORAGE_DIR"

log "Starting Warm → Cold rotation (converting logs older than $DAYS_OLD days to metrics)"

# Process each warm storage directory
find "$WARM_STORAGE_DIR" -type d -name "node-*_partition_*" -mtime +$DAYS_OLD 2>/dev/null | while read warm_dir; do
    log "Processing warm directory: $(basename "$warm_dir")"
    
    # Extract metrics from compressed logs
    find "$warm_dir" -name "*.gz" -mtime +$DAYS_OLD | while read gz_file; do
        log "  Converting: $(basename "$gz_file")"
        
        # Decompress and convert to Prometheus metrics
        gunzip -c "$gz_file" | python3 << 'PYTHON_EOF'
import json
import sys
import requests
from datetime import datetime

prometheus_url = "http://localhost:9091/metrics/job/log_archive"
metrics_sent = 0

for line in sys.stdin:
    try:
        log = json.loads(line)
        timestamp = int(datetime.now().timestamp() * 1000)
        level = log.get('level', 'INFO')
        service = log.get('service_name', 'unknown')
        host = log.get('host_name', 'unknown')
        
        # Create Prometheus metrics
        metrics = [
            f'hpc_cold_logs_total{{level="{level}",service="{service}",host="{host}"}} 1 {timestamp}',
            f'hpc_cold_log_bytes{{service="{service}"}} {len(line)} {timestamp}'
        ]
        
        if level == 'ERROR':
            metrics.append(f'hpc_cold_errors_total{{service="{service}"}} 1 {timestamp}')
        
        # Send to Pushgateway
        for metric in metrics:
            try:
                requests.post(prometheus_url, data=metric, timeout=2)
                metrics_sent += 1
            except:
                pass
    except:
        pass

print(f"    Sent {metrics_sent} metrics to Prometheus")
PYTHON_EOF
        
        # Move to cold storage archive
        mv "$gz_file" "$COLD_STORAGE_DIR/"
        ok "    Archived: $(basename "$gz_file")"
    done
    
    # Remove empty directory
    rmdir "$warm_dir" 2>/dev/null
done

# Show cold storage stats
cold_count=$(find "$COLD_STORAGE_DIR" -type f -name "*.gz" 2>/dev/null | wc -l)
cold_size=$(du -sh "$COLD_STORAGE_DIR" 2>/dev/null | cut -f1)

log "Warm → Cold rotation complete"
ok "Cold storage: $cold_count archived files, total size: $cold_size"