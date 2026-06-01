#!/bin/bash
# =============================================================================
# Rotate logs from warm to cold tier (runs weekly at 3 AM)
# Converts logs older than 30 days to Prometheus metrics and archives
# =============================================================================

WARM_DIR="/var/lib/victoriametrics-warm"
COLD_DIR="/var/lib/prometheus-cold"
PROMETHEUS_URL="http://node-3-pushgateway:9091/metrics/job/log_archive"
DAYS_OLD=30

echo "[$(date)] Starting warm to cold conversion..."

# Create cold directory
mkdir -p "$COLD_DIR"

find "$WARM_DIR" -type f -name "*.jsonl.gz" -mtime +$DAYS_OLD 2>/dev/null | while read file; do
    echo "  Processing: $(basename "$file")"
    
    # Decompress and convert to Prometheus metrics
    gunzip -c "$file" | python3 << 'PYTHON_EOF'
import json
import sys
import requests
from datetime import datetime

prometheus_url = "http://node-3-pushgateway:9091/metrics/job/log_archive"
metrics_sent = 0

for line in sys.stdin:
    try:
        log = json.loads(line)
        timestamp = int(datetime.now().timestamp() * 1000)
        level = log.get("level", "INFO")
        service = log.get("service_name", "unknown")
        
        # Create Prometheus metrics
        metrics = [
            f'hpc_archived_logs_total{{level="{level}",service="{service}"}} 1 {timestamp}',
            f'hpc_archived_log_bytes{{service="{service}"}} {len(line)} {timestamp}'
        ]
        
        if level == "ERROR":
            metrics.append(f'hpc_archived_errors_total{{service="{service}"}} 1 {timestamp}')
        
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
    mv "$file" "$COLD_DIR/"
    echo "  Archived: $(basename "$file")"
done

echo "[$(date)] Warm to cold conversion complete"

# Show stats
COLD_COUNT=$(find "$COLD_DIR" -type f -name "*.gz" 2>/dev/null | wc -l)
COLD_SIZE=$(du -sh "$COLD_DIR" 2>/dev/null | cut -f1)
echo "  Cold storage: $COLD_COUNT files, $COLD_SIZE"