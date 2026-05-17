#!/bin/bash
echo "=== Container Memory Usage ==="
docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}" | grep -E "node-|CONTAINER"
echo ""
echo "=== Total Docker Memory ==="
docker system df