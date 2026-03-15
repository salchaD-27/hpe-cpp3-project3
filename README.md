# VictoriaLogs HPC Observability Pipeline
Evaluating VictoriaLogs as a scalable log and event management
solution for HPC environments at University of Alaska Fairbanks (UAF).

## Pipeline Architecture
```
Simulator → Fluent Bit → Kafka → Logstash → VictoriaLogs → Grafana
```

## Components

| # | Component | Version | Port | Role |
|---|-----------|---------|------|------|
| 1 | HPC Simulator | Python 3.12 | — | Generates synthetic HPC log events |
| 2 | Fluent Bit | v4.2.3 | 2020 | Reads log files, forwards to Kafka |
| 3 | Apache Kafka | v3.9.2 KRaft | 9092 | Message queue / buffer |
| 4 | Logstash | v8.19.12 | 9600 | Transforms and routes logs |
| 5 | VictoriaLogs | v1.47.0 | 9428 | Log storage and query engine |
| 6 | Grafana | v12.4.0 | 3000 | Visualization and dashboards |

## Environment

- OS: Ubuntu 24.04 LTS (VirtualBox VM)
- RAM: 8GB | CPU: 4 cores | Disk: 80GB

## Quick Start
```bash
# Start all services
sudo systemctl start kafka victoria-logs fluent-bit logstash grafana-server hpc-simulator

# Verify pipeline
curl -s http://localhost:9428/metrics | grep rows_ingested
```

## Repository Structure
```
1_simulator/      HPC log generator (Python + systemd service)
2_fluent_bit/     Log collector config (tail + Kafka output)
3_kafka/          Message broker config (KRaft mode)
4_logstash/       Pipeline processor config
5_victorialogs/   Log storage service config
6_grafana/        Dashboard datasource config
docs/             Sample data and architecture notes
```

## Project Status

- Phase 1: ✅ Complete — full pipeline working end to end
- Phase 2: 📋 Planned — Docker and multi-node cluster
