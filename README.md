# HPC Log Pipeline — Multi-Node HA

10-node observability stack for HPC logs, replicated **3x across independent VictoriaLogs storage nodes**. Kill any one storage node — no data loss.

## Architecture

```
Simulator → Fluent Bit → Kafka → Logstash → vlagent → vmauth → 3× vlinsert → 3× vlstorage
                                                                                    ↑
                                                         Grafana / vmalert → vmauth (read)
```

vlagent fans out every write to all 3 replicas. vmauth handles auth + routing for both paths. vlselect can merge/dedup reads across replicas as an alternative to round-robin.

## Nodes

| # | Dir | Role |
|---|---|---|
| 1 | `node-1-pipeline/` | Simulator, Fluent Bit, Kafka, Logstash, Grafana, vmalert, Alertmanager |
| 2-4 | `node-2/3/4-vlinsert-*` | Write gateway, one per replica |
| 5-7 | `node-5/6/7-vlstorage-*` | Storage replica (365d retention) |
| 8 | `node-8-vlselect/` | Fan-out query across all 3 replicas |
| 9 | `node-9-vmauth/` | Auth + routing (`vmauth.yml`) |
| 10 | `node-10-vlagent/` | Replicates writes to all 3 paths |

Each is its own `docker-compose.yml` on the shared external network `multi-node-net`.

## Versions

| Component | Version |
|---|---|
| VictoriaLogs (vlinsert/vlstorage/vlselect) | v1.49.0 |
| vlagent | v1.50.0 |
| vmauth | latest |
| vmalert | latest |
| Apache Kafka | 4.2.0 |
| Logstash | 9.3.2 |
| Fluent Bit | 4.0.2 |
| Grafana | 11.6.15 |
| Alertmanager | latest |
| Python (simulator) | 3.12 |

## Quick Start

```bash
./2-start.sh      # start all nodes, dependency order
./1-stop.sh       # stop all nodes
./3-test.sh       # integration test suite
./4-ha-test.sh    # kill/restore storage nodes mid-stream, verify no data loss
```

| UI | URL | Auth |
|---|---|---|
| Grafana | http://localhost:3001 | admin/admin |
| vmauth | http://localhost:8427 | see below |
| vmalert | http://localhost:8881 | — |
| Alertmanager | http://localhost:9095 | — |
| vlstorage 1/2/3 (direct) | :8002 / :8003 / :8004 | — |

## Auth (vmauth.yml)

| User | Pass | Routes to |
|---|---|---|
| write1/2/3 | `hpc-write-pass-{1,2,3}` | vlinsert-1/2/3 |
| read | `hpc-read-pass` | all 3 storage nodes (or vlselect) |

```bash
curl -u write1:hpc-write-pass-1 -X POST "http://localhost:8427/insert/jsonline" \
  -d '{"_time":"2026-06-29T00:00:00Z","level":"INFO","_msg":"hello"}'

curl -u read:hpc-read-pass "http://localhost:8427/select/logsql/query?query=hello"
```

## Alerting

vmalert evaluates LogsQL rules every 30s from `node-1-pipeline/5-vmalert/alerting/vmalert/*.yml`, routes fired alerts to Alertmanager → Slack. Heartbeat rules (`cross-alerting/`) simulate fire/resolve lifecycle via asymmetric eval intervals — see `Cross-Alerting.md`.

## Repository Layout

```
.
├── node-1-pipeline/
│   ├── 1-generator/
│   │   ├── generator.py
│   │   ├── heartbeat.sh
│   │   ├── no_heartbeat.sh
│   │   ├── generated-logs/
│   │   └── logs-original/
│   │       ├── hpcmlog.json
│   │       ├── monitoring_service.json
│   │       ├── syslog.json
│   │       ├── sample_alerting_task3.json
│   │       └── dynamic_kv_ip_logs.json
│   ├── 2-fluent-bit/
│   │   ├── fluent-bit.conf
│   │   └── parsers.conf
│   ├── 3-logstash/
│   │   ├── hpc-pipeline.conf
│   │   └── logstash.yml
│   ├── 4-grafana/
│   │   ├── alerting-dashboard/
│   │   │   ├── hpc-alert-explorer.json
│   │   │   └── readme.md
│   │   ├── logs-dashboard/
│   │   │   ├── hpc-log-explorer.json
│   │   │   └── readme.md
│   │   └── provisioning/datasources/datasources.yml
│   ├── 5-vmalert/
│   │   ├── Cross-Alerting.md
│   │   └── alerting/
│   │       ├── alertmanager.yml
│   │       └── vmalert/
│   │           ├── alerts.yml
│   │           ├── MultiConditionSyslogAlert.yml
│   │           ├── SampleMessageDetected.yml
│   │           ├── UnifiedAlerts.yml
│   │           ├── dynamic_kv_replacement.yml
│   │           └── cross-alerting/
│   │               ├── heartbeat_detected.yml
│   │               ├── heartbeat_missing.yml
│   │               └── scripts/external/
│   │                   ├── alert_fire.sh
│   │                   └── alert_resolve.sh
│   └── docker-compose.yml
├── node-2-vlinsert-1/
│   └── docker-compose.yml          # write gateway → vlstorage-1
├── node-3-vlinsert-2/
│   └── docker-compose.yml          # write gateway → vlstorage-2
├── node-4-vlinsert-3/
│   └── docker-compose.yml          # write gateway → vlstorage-3
├── node-5-vlstorage-1/
│   ├── docker-compose.yml
│   └── storage/                    # storage replica 1 (gitignored)
├── node-6-vlstorage-2/
│   ├── docker-compose.yml
│   └── storage/                    # storage replica 2 (gitignored)
├── node-7-vlstorage-3/
│   ├── docker-compose.yml
│   └── storage/                    # storage replica 3 (gitignored)
├── node-8-vlselect/
│   └── docker-compose.yml          # fan-out query across replicas
├── node-9-vmauth/
│   ├── docker-compose.yml
│   └── vmauth.yml                  # auth + routing rules
├── node-10-vlagent/
│   ├── docker-compose.yml
│   └── vlagent-data/                # replication buffer (gitignored)
├── theory/                          # research notes, benchmarks, single-node reference (not deployed)
├── 1-stop.sh
├── 2-start.sh
├── 3-test.sh
├── 4-ha-test.sh
└── README.md
```

## `theory/`

Research notes, benchmarks, and an earlier single-node reference setup. Not deployed by `2-start.sh`. Explains *why* the design uses vlagent fan-out instead of native VictoriaLogs clustering.
