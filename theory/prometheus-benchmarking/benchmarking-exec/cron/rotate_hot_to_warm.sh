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






# #!/bin/bash
# # =============================================================================
# # Hot to Warm Tier Rotation
# # Moves logs older than 7 days from active storage to warm compressed storage
# # Runs daily at 2 AM
# # =============================================================================

# SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# cd "$REPO_ROOT"

# # Colors
# GREEN='\033[0;32m'
# YELLOW='\033[1;33m'
# BLUE='\033[0;34m'
# NC='\033[0m'

# log() { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
# ok() { echo -e "${GREEN}[OK]${NC} $1"; }
# warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# # Configuration
# HOT_STORAGE_DIRS=(
#     "node-3-vlstorage/storage"
#     "node-4-vlstorage/storage"
#     "node-3-vlstorage-hybrid/storage"
#     "node-4-vlstorage-hybrid/storage"
# )
# WARM_STORAGE_DIR="$REPO_ROOT/warm_storage"
# # DAYS_OLD=7
# DAYS_OLD=0.0067 # 1 min

# # Create warm storage directory
# mkdir -p "$WARM_STORAGE_DIR"

# log "Starting Hot → Warm rotation (moving logs older than $DAYS_OLD days)"

# for hot_dir in "${HOT_STORAGE_DIRS[@]}"; do
#     if [ ! -d "$hot_dir" ]; then
#         warn "Directory $hot_dir not found, skipping"
#         continue
#     fi
    
#     log "Processing: $hot_dir"
    
#     # Find and move partition directories older than DAYS_OLD
#     find "$hot_dir" -maxdepth 2 -type d -name "partitions" 2>/dev/null | while read partition_dir; do
#         parent_dir=$(dirname "$partition_dir")
        
#         # Check if directory is older than DAYS_OLD
#         if [ -d "$parent_dir" ]; then
#             dir_age=$(find "$parent_dir" -maxdepth 0 -mtime +$DAYS_OLD 2>/dev/null)
#             if [ -n "$dir_age" ]; then
#                 # Get partition name
#                 partition_name=$(basename "$parent_dir")
#                 node_name=$(basename "$(dirname "$parent_dir")")
                
#                 # Create warm storage subdirectory
#                 warm_target="$WARM_STORAGE_DIR/${node_name}_${partition_name}"
#                 mkdir -p "$warm_target"
                
#                 # Move and compress
#                 log "  Moving partition $partition_name from $node_name to warm storage"
                
#                 # Copy to warm storage first, then remove from hot
#                 cp -r "$parent_dir"/* "$warm_target/" 2>/dev/null
                
#                 # Compress JSON files in warm storage
#                 find "$warm_target" -name "*.json" -o -name "*.jsonl" | while read json_file; do
#                     gzip -f "$json_file"
#                     ok "    Compressed: $(basename "$json_file")"
#                 done
                
#                 # Remove from hot storage after successful copy
#                 rm -rf "$parent_dir"
#                 ok "  Removed from hot storage: $parent_dir"
#             fi
#         fi
#     done
# done

# # Show warm storage stats
# warm_count=$(find "$WARM_STORAGE_DIR" -type f -name "*.gz" 2>/dev/null | wc -l)
# warm_size=$(du -sh "$WARM_STORAGE_DIR" 2>/dev/null | cut -f1)

# log "Hot → Warm rotation complete"
# ok "Warm storage: $warm_count compressed files, total size: $warm_size"









# #!/bin/bash
# # =============================================================================
# # TEST VERSION: Hot to Warm Tier Rotation (2 MINUTES)
# # Moves logs older than 2 minutes from active storage to warm compressed storage
# # For testing purposes only - use with 2 minute threshold
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
# HOT_STORAGE_DIRS=(
#     "node-3-vlstorage/storage"
#     "node-4-vlstorage/storage"
#     "node-3-vlstorage-hybrid/storage"
#     "node-4-vlstorage-hybrid/storage"
# )
# WARM_STORAGE_DIR="$REPO_ROOT/warm_storage"

# # TEST CONFIGURATION: 2 MINUTES = 120 seconds
# # Using -mmin (minutes) instead of -mtime (days) for fine-grained control
# MINUTES_OLD=2

# # Create warm storage directory
# mkdir -p "$WARM_STORAGE_DIR"

# log "=========================================="
# log "TEST MODE: Hot → Warm rotation (moving logs older than ${MINUTES_OLD} MINUTES)"
# log "=========================================="

# for hot_dir in "${HOT_STORAGE_DIRS[@]}"; do
#     if [ ! -d "$hot_dir" ]; then
#         warn "Directory $hot_dir not found, skipping"
#         continue
#     fi
    
#     log "Processing: $hot_dir"
    
#     # Find partition directories modified more than MINUTES_OLD minutes ago
#     # -maxdepth 2 looks for partitions directory
#     # -type d finds directories
#     # -mmin +${MINUTES_OLD} finds files modified more than X minutes ago
#     find "$hot_dir" -maxdepth 2 -type d -name "partitions" -mmin +${MINUTES_OLD} 2>/dev/null | while read partition_dir; do
#         parent_dir=$(dirname "$partition_dir")
        
#         if [ -d "$parent_dir" ]; then
#             # Get partition name and node name
#             partition_name=$(basename "$parent_dir")
#             node_name=$(basename "$(dirname "$parent_dir")")
            
#             # Get modification time for logging
#             mod_time=$(stat -f "%Sm" "$parent_dir" 2>/dev/null || stat --format "%y" "$parent_dir" 2>/dev/null | cut -d'.' -f1)
            
#             log "  Found partition: $partition_name"
#             log "    Node: $node_name"
#             log "    Last modified: $mod_time"
#             log "    Age: More than ${MINUTES_OLD} minutes old"
            
#             # Create warm storage subdirectory
#             warm_target="$WARM_STORAGE_DIR/${node_name}_${partition_name}"
#             mkdir -p "$warm_target"
            
#             # Count files before moving
#             file_count=$(find "$parent_dir" -type f -name "*.json" -o -name "*.jsonl" 2>/dev/null | wc -l)
#             log "    Moving $file_count files to warm storage"
            
#             # Copy to warm storage first, then remove from hot
#             cp -r "$parent_dir"/* "$warm_target/" 2>/dev/null
            
#             # Compress JSON/JSONL files in warm storage
#             compress_count=0
#             find "$warm_target" -type f \( -name "*.json" -o -name "*.jsonl" \) | while read json_file; do
#                 original_size=$(stat -f "%z" "$json_file" 2>/dev/null || stat --format "%s" "$json_file" 2>/dev/null)
#                 gzip -f "$json_file"
#                 compressed_size=$(stat -f "%z" "${json_file}.gz" 2>/dev/null || stat --format "%s" "${json_file}.gz" 2>/dev/null)
                
#                 if [ -n "$original_size" ] && [ -n "$compressed_size" ]; then
#                     savings=$(echo "scale=1; (1 - $compressed_size / $original_size) * 100" | bc)
#                     ok "      Compressed: $(basename "$json_file") (${savings}% saved)"
#                 else
#                     ok "      Compressed: $(basename "$json_file")"
#                 fi
#                 compress_count=$((compress_count + 1))
#             done
            
#             # Remove from hot storage after successful copy
#             rm -rf "$parent_dir"
#             ok "    Removed from hot storage: $parent_dir"
#             log "    Compressed $compress_count files"
#         fi
#     done
# done

# # Show warm storage stats
# warm_count=$(find "$WARM_STORAGE_DIR" -type f -name "*.gz" 2>/dev/null | wc -l)
# warm_size=$(du -sh "$WARM_STORAGE_DIR" 2>/dev/null | cut -f1)
# warm_raw_size=$(find "$WARM_STORAGE_DIR" -name "*.gz" -exec gunzip -c {} \; 2>/dev/null | wc -c | awk '{print $1/1024/1024 " MB"}')

# log "=========================================="
# log "Hot → Warm rotation complete"
# ok "Warm storage summary:"
# ok "  Compressed files: $warm_count"
# ok "  Compressed size: $warm_size"
# ok "  Estimated raw size: $warm_raw_size"

# if [ -n "$warm_raw_size" ] && [ "$warm_raw_size" != "0 MB" ]; then
#     compression_ratio=$(echo "scale=1; $(echo $warm_size | sed 's/[^0-9.]//g') / $(echo $warm_raw_size | sed 's/[^0-9.]//g') * 100" | bc 2>/dev/null)
#     if [ -n "$compression_ratio" ]; then
#         savings=$(echo "scale=1; 100 - $compression_ratio" | bc)
#         ok "  Space saved: ${savings}% through compression"
#     fi
# fi
# log "=========================================="


#!/bin/bash
# =============================================================================
# TEST VERSION: Hot to Warm Tier Rotation (2 MINUTES)
# Only compresses actual log files (.jsonl), not metadata files
# =============================================================================
#!/bin/bash
# =============================================================================
# TEST VERSION: Hot to Warm Tier Rotation (2 MINUTES)
# =============================================================================
#!/bin/bash
# =============================================================================
# CORRECTED: Hot to Warm Tier Rotation - For Daily Partitions (YYYYMMDD)
# =============================================================================

#!/bin/bash
# =============================================================================
# TEST VERSION: Force move current partition (for testing only!)
# =============================================================================

cd /Users/salchad27/Desktop/clg/HPE/multi-node-simulation

WARM_STORAGE_DIR="./warm_storage"
mkdir -p "$WARM_STORAGE_DIR"

echo "=========================================="
echo "TEST: Forcing hot → warm rotation (moving current partition)"
echo "=========================================="

for node_dir in node-3-vlstorage node-4-vlstorage node-3-vlstorage-hybrid node-4-vlstorage-hybrid; do
    partitions_dir="$node_dir/storage/partitions"
    
    if [ -d "$partitions_dir" ]; then
        # Find the current partition (today's date)
        today_partition=$(ls -d "$partitions_dir"/20* 2>/dev/null | head -1)
        
        if [ -n "$today_partition" ]; then
            partition_name=$(basename "$today_partition")
            echo "  Moving partition: $partition_name from $node_dir"
            
            warm_target="$WARM_STORAGE_DIR/${node_dir}_${partition_name}"
            mkdir -p "$warm_target"
            
            # Copy and compress
            cp -r "$today_partition"/* "$warm_target/"
            
            find "$warm_target" -type f \( -name "*.bin" -o -name "*.db" \) | while read f; do
                gzip -f "$f"
                echo "    Compressed: $(basename "$f")"
            done
            
            # Remove original
            rm -rf "$today_partition"
            echo "    Removed original partition"
            
            # Recreate empty partition directory for new logs
            mkdir -p "$today_partition"
        fi
    fi
done

echo "=========================================="
echo "Done! Warm storage size: $(du -sh $WARM_STORAGE_DIR 2>/dev/null | cut -f1)"