# HPC Log Pipeline — Multi-Node VictoriaLogs Cluster

HPE CPP3 project — a distributed HPC log ingestion, storage, and querying pipeline built with VictoriaLogs, Kafka, Logstash, Fluent Bit, and Grafana.

---

## Project Structure

```
.
├── node-1-pipeline/
│   ├── 1-generator/
│   │   ├── generator.py
│   │   ├── logs-generated/
│   │   └── logs-original/
│   │       ├── hpcmlog.json
│   │       ├── monitoring_service.json
│   │       └── syslog.json
│   ├── 2-fluent-bit/
│   │   ├── fluent-bit.conf
│   │   └── parsers.conf
│   ├── 3-kafka/
│   ├── 4-logstash/
│   │   ├── hpc-pipeline.conf
│   │   └── logstash.yml
│   ├── 6-grafana/
│   │   ├──alerting-dashboard
│   │   │    ├── hpc-alert-explorer.json    
│   │   │    └── readme.md
│   │   ├── logs-dashboard
│   │   │    ├── hpc-log-explorer.json    
│   │   │    └── readme.md
│   │   ├── health-dashboard
│   │   │   ├── hpc-health-explorer.json    
│   │   │   └── readme.md
│   │   └── provisioning/datasources/datasources.yml
│   ├── 7-vmalert/
│   │   ├── alertmanager.yml
│   │   └── alerts.yml
│   ├── 8-victoriametrics/
│   │   └── scrape.yml
│   └── docker-compose.yml
├── node-2-vlinsert/
│   └── docker-compose.yml
├── node-3-vlstorage/
│   ├── docker-compose.yml
│   └── storage/
├── node-4-vlstorage/
│   ├── docker-compose.yml
│   └── storage/
├── node-5-vlselect/
│   └── docker-compose.yml
├── send.py
├── Inventory queries.md    ## contains query and result of Inventory data
├── start.sh
└── stop.sh
```

---

## Architecture

```
[generator.py]
      │ generates HPC log files
      ▼
[Fluent Bit]  ──tails JSONL──▶  [Kafka]  ──consumes──▶  [Logstash]
                                                               │
                                                    POST /insert/jsonline
                                                               │
                                                               ▼
                                                    [node-2-vlinsert :8001]
                                                        │           │
                                                        ▼           ▼
                                             [node-3-vlstorage] [node-4-vlstorage]
                                                  :8002               :8003
                                                        │           │
                                                        └─────┬─────┘
                                                              ▼
                                                   [node-5-vlselect :8004]
                                                              │
                                                    ┌─────────┴──────────┐
                                                    ▼                    ▼
                                                [Grafana]           [vmalert]
                                                  :3001               :8881
                                                                        │
                                                                        ▼
                                                                 [Alertmanager]
                                                                     :9095
```

### Inventory ingestion (new)

```
[inventory-data-bardpeak001.json]
              │
              ▼
         [send.py]
    one component type per run
    stamps real UTC timestamp
    tracks progress in sent_types.txt
              │
    POST /insert/jsonline
              │
              ▼
   [node-2-vlinsert :8001]
     log_source="inventory"
```

---

## Nodes

| Node | Container | Role | Host Port |
|------|-----------|------|-----------|
| Node 1 | pipeline | Generator, Fluent Bit, Kafka, Logstash, Grafana, vmalert, Alertmanager | see below |
| Node 2 | node-2-vlinsert | Write gateway — accepts log writes, fans out to storage | 8001 |
| Node 3 | node-3-vlstorage | Storage shard 1, 1yr retention | 8002 |
| Node 4 | node-4-vlstorage | Storage shard 2, 1yr retention | 8003 |
| Node 5 | node-5-vlselect | Query node — serves Grafana and vmalert | 8004 |

### Node 1 services

| Component | Host Port |
|-----------|-----------|
| Fluent Bit | 8081 |
| Kafka | 9094 |
| Logstash | 9601 |
| Grafana | 3001 |
| vmalert | 8881 |
| Alertmanager | 9095 |
| Kafka UI | 8080 |

---

## Service URLs

| Service | URL | Credentials |
|---------|-----|-------------|
| Grafana | http://localhost:3001 | admin / admin |
| Write API (vlinsert) | http://localhost:8001 | — |
| Query API (vlselect) | http://localhost:8004 | — |
| Storage node 3 | http://localhost:8002 | — |
| Storage node 4 | http://localhost:8003 | — |
| Kafka UI | http://localhost:8080 | — |

---

## Getting Started

### Prerequisites

- Docker and Docker Compose installed
- Python 3.x (for generator and inventory ingestion)

### Start the cluster

```bash
./start.sh
```

### Stop the cluster

```bash
./stop.sh
```

### Verify all containers are running

```bash
docker ps | grep -E "vl|kafka|logstash|grafana|fluent"
```

---

## Log Pipeline

The live log pipeline flows as follows:

1. `generator.py` reads sample log files from `logs-original/` and generates a continuous stream of JSONL log files into `logs-generated/`
2. Fluent Bit tails the generated files and publishes records to the Kafka topic `hpc-logs`
3. Logstash consumes from Kafka, transforms the records, and POSTs to vlinsert on `node-2-vlinsert:9428`
4. vlinsert shards the data across node-3 and node-4 vlstorage
5. Grafana and vmalert query via node-5 vlselect

### Log sources

| Stream | log_source value | Origin |
|--------|-----------------|--------|
| System logs | syslog | syslog.json |
| Monitoring | monitoring | monitoring_service.json |
| HPC logs | hpcmlog | hpcmlog.json |

---
