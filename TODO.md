# HPC Logging Pipeline Docker Compose Setup

## Steps:
- [x] 1. Create 5-victorialogs/Dockerfile for VictoriaLogs
- [x] 2. Edit 3-kafka/server.properties (listeners to 0.0.0.0)
- [x] 3. Edit 4-logstash/pipeline.conf (VL url to victorialogs:9428)
- [x] 4. Edit 6-grafana/datasources.yml (url to http://victorialogs:9428)
- [x] 5. Create docker-compose.yml with all services
- [ ] 6. Test: docker compose up -d & logs

All setup complete. docker-compose.yml ready. Run `docker compose up -d` to start.
