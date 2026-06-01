#!/bin/bash
# =============================================================================
# Rotate logs from hot to warm tier (runs daily at 2 AM)
# Moves logs older than 7 days from JSON storage to warm tier
# =============================================================================

LOG_DIR="/var/lib/victoriametrics"
WARM_DIR="/var/lib/victoriametrics-warm"
DAYS_OLD=7

echo "[$(date)] Starting hot to warm rotation..."

# Create warm directory if not exists
mkdir -p "$WARM_DIR"

# Find and move logs older than DAYS_OLD
find "$LOG_DIR" -type f -name "*.jsonl" -mtime +$DAYS_OLD 2>/dev/null | while read file; do
    echo "  Moving: $(basename "$file")"
    mv "$file" "$WARM_DIR/"
    
    # Compress warm logs to save space
    gzip -f "$WARM_DIR/$(basename "$file")"
done

echo "[$(date)] Hot to warm rotation complete"

# Log rotation stats
WARM_COUNT=$(find "$WARM_DIR" -type f -name "*.gz" 2>/dev/null | wc -l)
WARM_SIZE=$(du -sh "$WARM_DIR" 2>/dev/null | cut -f1)
echo "  Warm storage: $WARM_COUNT files, $WARM_SIZE"