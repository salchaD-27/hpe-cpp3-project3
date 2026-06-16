# #!/bin/bash
echo "Starting HPC Log Pipeline with HA + Deduplication..."

# Create Docker network
docker network create multi-node-net 2>/dev/null || echo "Network already exists"

# Start storage nodes (order matters)
echo "Starting storage nodes (3 tiers)..."
cd node-5-vlstorage-1 && docker compose up -d
cd ..
cd node-6-vlstorage-2 && docker compose up -d
cd ..
cd node-7-vlstorage-3 && docker compose up -d
cd ..

sleep 5

# Start vlinsert nodes
echo "Starting vlinsert nodes (3 write gateways)..."
cd node-2-vlinsert-1 && docker compose up -d
cd ..
cd node-3-vlinsert-2 && docker compose up -d
cd ..
cd node-4-vlinsert-3 && docker compose up -d
cd ..

sleep 3

# Start vlselect with dedup
echo "Starting vlselect with deduplication..."
cd node-8-vlselect && docker compose up -d
cd ..

sleep 3

# Start vmauth
echo "Starting vmauth load balancer..."
cd node-9-vmauth && docker compose up -d
cd ..

sleep 3

# Start vlagent
echo "Starting vlagent for log replication..."
cd node-10-vlagent && docker compose up -d
cd ..

sleep 3

# Start pipeline
echo "Starting pipeline..."
cd node-1-pipeline && docker compose up -d
cd ..

sleep 5

# Status
echo ""
echo "=== Container Status ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "=== Access Points ==="
echo "   Grafana:        http://localhost:3001 (admin/admin)"
echo "   vmauth (LB):    http://localhost:8427"
echo "   Write:          http://localhost:8427/write1/insert/jsonline"
echo "                   http://localhost:8427/write2/insert/jsonline"
echo "                   http://localhost:8427/write3/insert/jsonline"
echo "   Read:           http://localhost:8427/read/select/logsql/query"
echo "   vlagent:        http://localhost:9429"
echo ""
echo "Storage Nodes:"
echo "   vlstorage-1:    http://localhost:8002"
echo "   vlstorage-2:    http://localhost:8003"
echo "   vlstorage-3:    http://localhost:8004"
echo ""
echo "All components started!"