#!/bin/bash

set -e

echo "===================================="
echo "Stopping Single Node Log Pipeline..."
echo "===================================="

docker compose down

echo
echo "Pipeline stopped successfully!"