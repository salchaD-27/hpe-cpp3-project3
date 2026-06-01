#!/bin/bash
# =============================================================================
# Setup Cron Jobs for Storage Tier Rotation
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Make scripts executable
chmod +x "$SCRIPT_DIR/rotate_hot_to_warm.sh"
chmod +x "$SCRIPT_DIR/rotate_warm_to_cold.sh"
chmod +x "$SCRIPT_DIR/view_tiers.sh"

# Create crontab entries
(crontab -l 2>/dev/null; echo "# Hot to Warm rotation - Daily at 2 AM") | crontab -
(crontab -l 2>/dev/null; echo "0 2 * * * $SCRIPT_DIR/rotate_hot_to_warm.sh >> $REPO_ROOT/logs/storage_rotation.log 2>&1") | crontab -

(crontab -l 2>/dev/null; echo "# Warm to Cold rotation - Weekly on Sunday at 3 AM") | crontab -
(crontab -l 2>/dev/null; echo "0 3 * * 0 $SCRIPT_DIR/rotate_warm_to_cold.sh >> $REPO_ROOT/logs/storage_rotation.log 2>&1") | crontab -

echo "✅ Cron jobs installed:"
echo "   - Daily 2 AM: Hot → Warm rotation"
echo "   - Weekly Sunday 3 AM: Warm → Cold rotation"
echo ""
echo "📊 View tier status: $SCRIPT_DIR/view_tiers.sh"
echo "📝 Logs: $REPO_ROOT/logs/storage_rotation.log"