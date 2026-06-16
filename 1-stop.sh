#!/bin/bash

echo "Stopping HPC Log Pipeline with HA + Deduplication..."

# Function to stop a docker compose project safely
stop_compose() {
    local dir="$1"
    local name="$2"
    
    if [ -d "$dir" ]; then
        echo "Stopping $name..."
        cd "$dir" 2>/dev/null || { echo "  ⚠ Cannot enter $dir"; return 1; }
        docker compose down --remove-orphans 2>&1 | grep -v "no such service" || true
        cd ..
        echo "  ✓ $name stopped"
    else
        echo "  ⚠ $dir not found - skipping"
    fi
}

# Stop in reverse order (pipeline first, then dependencies)
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Stopping components in reverse order..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1. Pipeline (depends on everything)
stop_compose "node-1-pipeline" "Pipeline (Grafana, vmalert, Logstash, Kafka, etc.)"

# 2. vlagent (sends to vmauth)
stop_compose "node-10-vlagent" "vlagent"
stop_compose "node-10-vlagent-1" "vlagent-1" 2>/dev/null
stop_compose "node-10-vlagent-2" "vlagent-2" 2>/dev/null
stop_compose "node-10-vlagent-3" "vlagent-3" 2>/dev/null

# 3. vmauth (routes to vlselect/vlinsert)
stop_compose "node-9-vmauth" "vmauth"

# 4. vlselect (queries storage nodes)
stop_compose "node-8-vlselect" "vlselect"

# 5. vlinsert nodes (write to storage)
stop_compose "node-2-vlinsert-1" "vlinsert-1"
stop_compose "node-3-vlinsert-2" "vlinsert-2"
stop_compose "node-4-vlinsert-3" "vlinsert-3"

# 6. storage nodes (last)
stop_compose "node-5-vlstorage-1" "vlstorage-1"
stop_compose "node-6-vlstorage-2" "vlstorage-2"
stop_compose "node-7-vlstorage-3" "vlstorage-3"

# Force remove any remaining containers with node- prefix
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Cleaning up any remaining containers..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

REMAINING=$(docker ps -a --filter "name=node-" --format "{{.Names}}" 2>/dev/null)
if [ -n "$REMAINING" ]; then
    echo "Removing remaining containers:"
    echo "$REMAINING" | while read name; do
        echo "  Stopping and removing: $name"
        docker stop "$name" 2>/dev/null
        docker rm "$name" 2>/dev/null
    done
else
    echo "✓ No remaining containers with 'node-' prefix"
fi

# Optional: Remove the network (uncomment if you want full reset)
# echo ""
# echo "Removing Docker network..."
# docker network rm multi-node-net 2>/dev/null && echo "✓ Network removed" || echo "⚠ Network not found or in use"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ All components stopped!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Show remaining containers (if any)
REMAINING_CONTAINERS=$(docker ps -a --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | grep -v "NAMES" | head -10)
if [ -n "$REMAINING_CONTAINERS" ]; then
    echo ""
    echo "Remaining containers (if any):"
    echo "$REMAINING_CONTAINERS"
else
    echo ""
    echo "✓ No containers remaining"
fi