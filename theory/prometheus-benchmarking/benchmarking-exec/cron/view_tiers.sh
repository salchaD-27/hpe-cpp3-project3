#!/bin/bash
# =============================================================================
# View Storage Tier Status
# Shows distribution of logs across Hot, Warm, and Cold tiers
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

print_header() {
    echo ""
    echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}  $1${NC}"
    echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_header "STORAGE TIER STATUS"

# =============================================================================
# HOT TIER (Active Storage Nodes)
# =============================================================================
echo -e "${GREEN}${BOLD}🔥 HOT TIER (Active Storage - Last 7 days)${NC}"
echo ""

for node in node-3-vlstorage node-4-vlstorage node-3-vlstorage-hybrid node-4-vlstorage-hybrid; do
    port=""
    case $node in
        node-3-vlstorage) port=8002 ;;
        node-4-vlstorage) port=8003 ;;
        node-3-vlstorage-hybrid) port=8005 ;;
        node-4-vlstorage-hybrid) port=8006 ;;
    esac
    
    count=$(curl -s "http://localhost:$port/select/logsql/query?query=*%20%7C%20count()" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(list(d.values())[0] if d else 0)" 2>/dev/null || echo "0")
    
    # Get storage size
    size_bytes=$(docker exec "$node" du -sb /storage 2>/dev/null | cut -f1 || echo "0")
    size_mb=$(echo "scale=2; $size_bytes / 1024 / 1024" | bc)
    
    echo "  📁 $node"
    echo "     Logs: $count"
    echo "     Size: $size_mb MB"
    echo ""
done

# =============================================================================
# WARM TIER (Compressed Storage)
# =============================================================================
echo -e "${YELLOW}${BOLD}🌡️ WARM TIER (Compressed Storage - Days 8-30)${NC}"
echo ""

if [ -d "warm_storage" ]; then
    warm_files=$(find warm_storage -type f -name "*.gz" 2>/dev/null | wc -l)
    warm_size=$(du -sh warm_storage 2>/dev/null | cut -f1)
    warm_original_size=$(find warm_storage -name "*.gz" -exec gunzip -c {} \; 2>/dev/null | wc -c | awk '{print $1/1024/1024 " MB"}')
    
    echo "  📦 Location: warm_storage/"
    echo "     Compressed files: $warm_files"
    echo "     Compressed size: $warm_size"
    echo "     Estimated original size: $warm_original_size"
    echo "     Compression ratio: $(du -sb warm_storage 2>/dev/null | cut -f1 | awk '{print $1/1024/1024}') MB compressed vs ${warm_original_size} original"
    
    # Show oldest and newest files
    oldest=$(find warm_storage -type f -name "*.gz" -printf '%T@ %p\n' 2>/dev/null | sort -n | head -1 | cut -d' ' -f2-)
    newest=$(find warm_storage -type f -name "*.gz" -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [ -n "$oldest" ]; then
        echo "     Oldest file: $(basename "$oldest")"
    fi
    if [ -n "$newest" ]; then
        echo "     Newest file: $(basename "$newest")"
    fi
else
    echo "  ⚠️ Warm storage directory not found"
fi

# =============================================================================
# COLD TIER (Prometheus Metrics)
# =============================================================================
echo ""
echo -e "${BLUE}${BOLD}❄️ COLD TIER (Prometheus Metrics - Days 31-365)${NC}"
echo ""

if [ -d "cold_storage/metrics" ]; then
    cold_files=$(find cold_storage/metrics -type f -name "*.gz" 2>/dev/null | wc -l)
    cold_size=$(du -sh cold_storage/metrics 2>/dev/null | cut -f1)
    
    echo "  📊 Location: cold_storage/metrics/"
    echo "     Archived files: $cold_files"
    echo "     Total size: $cold_size"
    
    # Check Prometheus for cold metrics
    echo ""
    echo "  📈 Prometheus Cold Metrics:"
    curl -s "http://localhost:9090/api/v1/query?query=count(hpc_cold_logs_total)" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print('     hpc_cold_logs_total: ' + str(d.get('data',{}).get('result',[])))" 2>/dev/null || echo "     No cold metrics found"
else
    echo "  ⚠️ Cold storage directory not found"
fi

# =============================================================================
# Storage Summary
# =============================================================================
echo ""
echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}${BOLD}                              STORAGE TIER SUMMARY${NC}"
echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Calculate totals
hot_logs=0
for port in 8002 8003 8005 8006; do
    count=$(curl -s "http://localhost:$port/select/logsql/query?query=*%20%7C%20count()" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(list(d.values())[0] if d else 0)" 2>/dev/null || echo "0")
    hot_logs=$((hot_logs + count))
done

echo "  🔥 Hot Tier:  $hot_logs logs (active, full-text searchable)"
echo "  🌡️ Warm Tier: $warm_files files (compressed, reduced storage)"
echo "  ❄️ Cold Tier: $cold_files metrics (Prometheus, long-term retention)"
echo ""

# Storage savings calculation
if [ -d "warm_storage" ]; then
    warm_compressed_mb=$(du -sb warm_storage 2>/dev/null | cut -f1 | awk '{print $1/1024/1024}')
    warm_original_mb=$(echo "$warm_original_size" | sed 's/ MB//')
    if [ -n "$warm_original_mb" ] && [ "$warm_original_mb" != "0" ]; then
        savings=$(echo "scale=1; (1 - $warm_compressed_mb / $warm_original_mb) * 100" | bc)
        echo "  💾 Storage Savings:"
        echo "     Warm tier compression: ${savings}% space saved"
        echo "     Cold tier (Prometheus): ~70% additional savings vs raw logs"
    fi
fi

echo ""