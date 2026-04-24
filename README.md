# HPC Log Pipeline

A single-node observability pipeline for HPC (High Performance Computing) logs. Streams structured JSON logs through a collect → buffer → transform → store → visualize → alert stack, all running locally via Docker Compose.

---

## Pipeline Architecture

```
Simulator → Fluent Bit → Kafka → Logstash → VictoriaLogs → Grafana
                                                  ↓
                                             vmalert → Alertmanager
```

| Stage | Tool | Role |
|---|---|---|
| Generate | Log Simulator (Python 3.12) | Replays original JSON logs as JSONL at a configurable rate |
| Collect | Fluent Bit 4.0.2 | Tails JSONL files, parses, and forwards to Kafka |
| Buffer | Apache Kafka 4.0.2 | Decouples ingestion from processing; durable message queue |
| Transform | Logstash 9.2.8 | Consumes from Kafka, enriches/filters, ships to VictoriaLogs |
| Store | VictoriaLogs v1.49.0 | High-performance log storage with 1-year retention |
| Visualize | Grafana 11.4.0 | Dashboards powered by the VictoriaMetrics Logs datasource plugin |
| Alert | vmalert (latest) | Evaluates LogsQL alert rules against VictoriaLogs every 30s |
| Route | Alertmanager v0.31.1 | Routes fired alerts to Slack, email, or webhook |

---

## Service Reference

| Service | Image | Port | Purpose |
|---|---|---|---|
| Fluent Bit | `cr.fluentbit.io/fluent/fluent-bit:4.0.2` | 2020 | HTTP metrics endpoint |
| Kafka | `apache/kafka:4.0.2` | 9092 | Broker (KRaft mode, no ZooKeeper) |
| Kafka UI | `provectuslabs/kafka-ui:latest` | 8080 | Web UI for topic/consumer inspection |
| Logstash | `docker.elastic.co/logstash/logstash:9.2.8` | 9600 | Pipeline monitoring API |
| VictoriaLogs | `victoriametrics/victoria-logs:v1.49.0` | 9428 | HTTP API + built-in query UI |
| Grafana | `grafana/grafana:11.4.0` | 3000 | Dashboards (admin / admin) |
| vmalert | `victoriametrics/vmalert:latest` | 8880 | Alert rule evaluation UI |
| Alertmanager | `prom/alertmanager:v0.31.1` | 9093 | Alert management UI |

---

## Kafka Configuration

Kafka runs in **KRaft mode** (no ZooKeeper dependency) as a combined broker + controller on a single node.

| Setting | Value |
|---|---|
| Mode | KRaft (broker + controller) |
| Partitions | 6 |
| Replication factor | 1 (single node) |
| Log retention | 24 hours |
| Auto-create topics | Enabled |
| Listener | `PLAINTEXT://kafka:9092` |
| Controller quorum | `1@kafka:9093` |

---

## VictoriaLogs Configuration

| Setting | Value |
|---|---|
| Listen address | `:9428` |
| Storage path | `/storage` (Docker volume) |
| Retention period | 1 year |

---

## Grafana Configuration

| Setting | Value |
|---|---|
| Admin credentials | `admin / admin` |
| Datasource plugin | `victoriametrics-logs-datasource` (auto-installed) |
| Dashboard | `grafana/hpc-dashboard-v14.json` (provisioned) |
| Datasource provisioning | `grafana/provisioning/datasources/` |
| Sign-up | Disabled |

---

## Alerting

**vmalert** evaluates rules from `alerting/alerts.yml` against VictoriaLogs using LogsQL every **30 seconds** (`-evaluationInterval=30s`, `-datasource.queryStep=30s`).

Fired alerts are forwarded to **Alertmanager** at `http://alertmanager:9093`, which routes them to configured receivers (Slack, email, webhook) defined in `alerting/alertmanager.yml`.

---

## Logstash Dead Letter Queue (DLQ)

Events that fail processing are written to a Dead Letter Queue at `data/logstash-dlq/` (bind-mounted). This prevents data loss on transformation errors and allows replaying failed events.

---

## Log Sources

The simulator reads seed files from `scripts/logs-original/` and streams them as JSONL into `generated-logs/` at a configurable replay rate. Fluent Bit tails those files using the config in `configs/fluent-bit/fluent-bit.conf` with custom parsers in `parsers.conf`.

Three log types are supported:

| Log type | Seed file | Generated file |
|---|---|---|
| HPC Manager | `hpcmlog.json` | `hpcmlog.jsonl` |
| Monitoring Service | `monitoring_service.json` | `monitoring_service.jsonl` |
| Syslog | `syslog.json` | `syslog.jsonl` |

---

## File Structure

```
hpc-log-pipeline/
├── docker-compose.yml
├── .env
├── alerting/
│   ├── alerts.yml              # vmalert rule definitions
│   └── alertmanager.yml        # alert routing config
├── configs/
│   ├── fluent-bit/
│   │   ├── fluent-bit.conf     # input/filter/output config
│   │   └── parsers.conf        # custom JSONL parser
│   └── logstash/
│       ├── hpc-pipeline.conf   # Kafka input → filter → VictoriaLogs output
│       └── logstash.yml        # Logstash node settings
├── grafana/
│   ├── hpc-dashboard.json  # provisioned dashboard
│   └── provisioning/
│       └── datasources/        # auto-configured VictoriaLogs datasource
├── scripts/
│   ├── simulator.py            # log replay simulator
│   └── logs-original/
│       ├── hpcmlog.json
│       ├── monitoring_service.json
│       └── syslog.json
├── data/
│   └── logstash-dlq/           # dead letter queue (runtime, git-ignored)
└── generated-logs/             # simulator output (runtime, git-ignored)
```

---

## Quick Start

**Prerequisites:** Docker Engine with Compose V2.

```bash
# Start all services
docker compose up -d

# Check service health
docker compose ps

# Stream logs from any service
docker compose logs -f logstash
```

| UI | URL | Credentials |
|---|---|---|
| Grafana | http://localhost:3000 | admin / admin |
| Kafka UI | http://localhost:8080 | — |
| VictoriaLogs | http://localhost:9428 | — |
| vmalert | http://localhost:8880 | — |
| Alertmanager | http://localhost:9093 | — |
| Fluent Bit metrics | http://localhost:2020 | — |
| Logstash monitoring | http://localhost:9600 | — |

```bash
# Stop and remove containers (keep volumes)
docker compose down

# Full teardown including volumes
docker compose down -v
```

---

## Volumes

| Volume | Used by | Purpose |
|---|---|---|
| `kafka-data` | Kafka | Topic and partition data |
| `victorialogs-data` | VictoriaLogs | Log storage |
| `grafana-data` | Grafana | Dashboards, users, settings |
| `logstash-dlq` | Logstash | Dead letter queue (bind mount) |

All services communicate over an isolated Docker bridge network named `pipeline`.

## Logs in FluentBit

<img width="1919" height="1199" alt="image" src="https://github.com/user-attachments/assets/00819d19-4c53-4c4a-8532-4647b7dbfffc" />

## Logs in Kafka

<img width="1919" height="1199" alt="image" src="https://github.com/user-attachments/assets/68c98a36-fa35-49f7-b06e-34e7dae9ba82" />

<img width="1915" height="1138" alt="image" src="https://github.com/user-attachments/assets/a5bafae8-8bb9-47b8-9d66-5694072f4556" />

## Logs in Logstash

<img width="1917" height="1199" alt="image" src="https://github.com/user-attachments/assets/2e1ba9bb-50a4-4999-b17e-3ab52f22b627" />

<img width="1919" height="1199" alt="image" src="https://github.com/user-attachments/assets/ce0d9536-4cb3-4a65-ab08-b87547dc999e" />

## Logs in Victoria Logs

<img width="1919" height="995" alt="image" src="https://github.com/user-attachments/assets/feb82bce-ddaa-4c04-81d5-12fb9ad21893" />

<img width="569" height="296" alt="image" src="https://github.com/user-attachments/assets/06e54112-0a15-48d4-ae3e-97c9f6f785fc" />

## Grafana Dashboard

<img width="1569" height="915" alt="image" src="https://github.com/user-attachments/assets/da99339a-de98-40a2-8527-de75263f35b1" />

<img width="1581" height="905" alt="image" src="https://github.com/user-attachments/assets/4c6d27e8-c115-4fa1-9560-14fd742b901e" />

<img width="1574" height="913" alt="image" src="https://github.com/user-attachments/assets/b6105870-0d63-4a0a-a283-5e1ab4feacad" />

<img width="820" height="111" alt="image" src="https://github.com/user-attachments/assets/51843548-a5f7-4a70-81bf-7b690ca27866" /> added the filter and search options















