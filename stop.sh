#!/bin/bash

echo "Stopping all nodes..."

cd node-1-ingest && docker-compose down && cd ..
cd node-2-storage && docker-compose down && cd ..
cd node-3-storage && docker-compose down && cd ..
cd node-4-query && docker-compose down && cd ..
cd node-5-orch && docker-compose down && cd ..

echo "All nodes stopped."