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
