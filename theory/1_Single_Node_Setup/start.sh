#!/bin/bash

set -e

echo "===================================="
echo "Starting Single Node Log Pipeline..."
echo "===================================="

docker compose up -d

echo
echo "Pipeline started successfully!"
echo
docker compose ps