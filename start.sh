#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo ""
echo "Multi-Node Simulation (1-2-2)"
echo ""

# Preflight port checks (fail fast; do NOT auto-remap)
# Ports used by the stack on the host:
# - Device 1 (vlinsert): 8001
# - Device 2 (storage): 8002
# - Device 3 (storage): 8003
# - Device 4 (query): 8004, Grafana 3001, vmalert 8881
# - Device 5 (orchestrator): 8005
# - (internal select fallback uses 8006)
# Note: Kafka controller listener uses an internal port and may conflict with an already-running local Kafka.
# We do NOT preflight-check 9093 to avoid failing the whole simulation when local Kafka is running.
PORTS=(8001 8002 8003 8004 8005 8006 3001 8881)


is_port_free() {
  local port="$1"
  if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

for p in "${PORTS[@]}"; do
  if ! is_port_free "$p"; then
    echo "ERROR: Required port $p is already in use on the host." >&2
    echo "Run ./stop.sh to stop containers, or stop the conflicting process using this port." >&2
    exit 1
  fi
done

echo "Port preflight: OK"


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