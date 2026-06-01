# #!/bin/bash
# # =============================================================================
# # Rotate logs from hot to warm tier (runs daily at 2 AM)
# # Moves logs older than 7 days from JSON storage to warm tier
# # =============================================================================

# LOG_DIR="/var/lib/victoriametrics"
# WARM_DIR="/var/lib/victoriametrics-warm"
# DAYS_OLD=7

# echo "[$(date)] Starting hot to warm rotation..."

# # Create warm directory if not exists
# mkdir -p "$WARM_DIR"

# # Find and move logs older than DAYS_OLD
# find "$LOG_DIR" -type f -name "*.jsonl" -mtime +$DAYS_OLD 2>/dev/null | while read file; do
#     echo "  Moving: $(basename "$file")"
#     mv "$file" "$WARM_DIR/"
    
#     # Compress warm logs to save space
#     gzip -f "$WARM_DIR/$(basename "$file")"
# done

# echo "[$(date)] Hot to warm rotation complete"

# # Log rotation stats
# WARM_COUNT=$(find "$WARM_DIR" -type f -name "*.gz" 2>/dev/null | wc -l)
# WARM_SIZE=$(du -sh "$WARM_DIR" 2>/dev/null | cut -f1)
# echo "  Warm storage: $WARM_COUNT files, $WARM_SIZE"


#!/bin/bash
# =============================================================================
# Hot to Warm Tier Rotation
# Moves logs older than 7 days from active storage to warm compressed storage
# Runs daily at 2 AM
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
HOT_STORAGE_DIRS=(
    "node-3-vlstorage/storage"
    "node-4-vlstorage/storage"
    "node-3-vlstorage-hybrid/storage"
    "node-4-vlstorage-hybrid/storage"
)
WARM_STORAGE_DIR="$REPO_ROOT/warm_storage"
DAYS_OLD=7

# Create warm storage directory
mkdir -p "$WARM_STORAGE_DIR"

log "Starting Hot → Warm rotation (moving logs older than $DAYS_OLD days)"

for hot_dir in "${HOT_STORAGE_DIRS[@]}"; do
    if [ ! -d "$hot_dir" ]; then
        warn "Directory $hot_dir not found, skipping"
        continue
    fi
    
    log "Processing: $hot_dir"
    
    # Find and move partition directories older than DAYS_OLD
    find "$hot_dir" -maxdepth 2 -type d -name "partitions" 2>/dev/null | while read partition_dir; do
        parent_dir=$(dirname "$partition_dir")
        
        # Check if directory is older than DAYS_OLD
        if [ -d "$parent_dir" ]; then
            dir_age=$(find "$parent_dir" -maxdepth 0 -mtime +$DAYS_OLD 2>/dev/null)
            if [ -n "$dir_age" ]; then
                # Get partition name
                partition_name=$(basename "$parent_dir")
                node_name=$(basename "$(dirname "$parent_dir")")
                
                # Create warm storage subdirectory
                warm_target="$WARM_STORAGE_DIR/${node_name}_${partition_name}"
                mkdir -p "$warm_target"
                
                # Move and compress
                log "  Moving partition $partition_name from $node_name to warm storage"
                
                # Copy to warm storage first, then remove from hot
                cp -r "$parent_dir"/* "$warm_target/" 2>/dev/null
                
                # Compress JSON files in warm storage
                find "$warm_target" -name "*.json" -o -name "*.jsonl" | while read json_file; do
                    gzip -f "$json_file"
                    ok "    Compressed: $(basename "$json_file")"
                done
                
                # Remove from hot storage after successful copy
                rm -rf "$parent_dir"
                ok "  Removed from hot storage: $parent_dir"
            fi
        fi
    done
done

# Show warm storage stats
warm_count=$(find "$WARM_STORAGE_DIR" -type f -name "*.gz" 2>/dev/null | wc -l)
warm_size=$(du -sh "$WARM_STORAGE_DIR" 2>/dev/null | cut -f1)

log "Hot → Warm rotation complete"
ok "Warm storage: $warm_count compressed files, total size: $warm_size"