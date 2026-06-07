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
