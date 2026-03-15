
# VictoriaLogs HPC Observability Pipeline

Evaluating VictoriaLogs as a scalable log management solution for HPC environments.

## Pipeline
```
Simulator → Fluent Bit → Kafka → Logstash → VictoriaLogs → Grafana
```

## Components

| Component      | Version  | Port |
|----------------|----------|------|
| HPC Simulator  | Python 3.12 | —  |
| Fluent Bit     | v4.2.3   | 2020 |
| Apache Kafka   | v3.9.2   | 9092 |
| Logstash       | v8.19.12 | 9600 |
| VictoriaLogs   | v1.47.0  | 9428 |
| Grafana        | v12.4.0  | 3000 |

## Quick Start
```bash
sudo systemctl start kafka victoria-logs fluent-bit logstash grafana-server hpc-simulator
```

## Verify Pipeline
```bash
curl -s http://localhost:9428/metrics | grep rows_ingested
```

## Environment

- OS: Ubuntu 24.04 LTS (VirtualBox VM)
- RAM: 8GB | CPU: 4 cores | Disk: 80GB

## Project Structure
```
config/          — all service configuration files
simulator/       — HPC log generator (Python)
docs/            — sample data and documentation
```

## Status

- Phase 1: ✅ Complete — full pipeline working
- Phase 2: 📋 Planned — Docker + multi-node cluster
