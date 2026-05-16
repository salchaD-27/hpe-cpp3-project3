#!/bin/bash

set -e

echo ""
echo "Multi-Node Simulation (1-2-2)"
echo ""

# Create necessary directories
mkdir -p node-2-storage/storage
mkdir -p node-3-storage/storage
mkdir -p node-1-ingest/1-log-gen/logs-generated

# Build log generator image
echo "Building log generator..."
cd node-1-ingest/1-log-gen
docker build -t log-generator:latest .
cd ../..

# Start storage nodes first
echo "Starting storage nodes (Device 2 & 3)..."
cd node-2-storage && docker-compose up -d && cd ..
cd node-3-storage && docker-compose up -d && cd ..

sleep 5

# Start ingestion node
echo "Starting ingestion node (Device 1)..."
cd node-1-ingest && docker-compose up -d && cd ..

sleep 10

# Start query node
echo "Starting query node (Device 4)..."
cd node-4-query && docker-compose up -d && cd ..

sleep 5

# Start orchestrator node
echo "Starting orchestrator node (Device 5)..."
cd node-5-orch && docker-compose up -d && cd ..

echo ""
echo "All nodes started!"
echo ""
echo "Access Points:"
echo "  Device 1 (Ingest):"
echo "    - vlinsert: http://localhost:8001"
echo "    - Fluent Bit: http://localhost:8081/metrics"
echo "    - Logstash: http://localhost:9601"
echo "  Device 2 (Storage): http://localhost:8002"
echo "  Device 3 (Storage): http://localhost:8003"
echo "  Device 4 (Query):"
echo "    - Grafana: http://localhost:3001 (admin/admin)"
echo "    - vmalert: http://localhost:8881"
echo "  Device 5 (Orchestrator):"
echo "    - Query LB: http://localhost:8005"
echo ""
echo "Test query: curl 'http://localhost:8005/select/logsql/query?query=*%20%7C%20count()'"
echo ""