# VictoriaLogs — Log Storage and Query Engine

VictoriaLogs stores all log events with 30-day retention using
columnar compression. Provides LogsQL query API used by Grafana.

## Role in Pipeline
```
Logstash POST /insert/jsonline
        ↓
   VictoriaLogs
   - stores compressed columnar data
   - indexes all fields for fast search
   - partitions by day for efficient retention
        ↓
Grafana queries via /select/logsql/query
```

## Installation
```bash
# Download from dedicated VictoriaLogs repository
wget https://github.com/VictoriaMetrics/VictoriaLogs/releases/download/\
v1.47.0/victoria-logs-linux-amd64-v1.47.0.tar.gz

tar -xzf victoria-logs-linux-amd64-v1.47.0.tar.gz
sudo mv victoria-logs-prod /usr/local/bin/victoria-logs
sudo chmod +x /usr/local/bin/victoria-logs

# Create data directory and user
sudo useradd -r -s /bin/false victorialogs
sudo mkdir -p /var/lib/victoria-logs/data
sudo chown -R victorialogs:victorialogs /var/lib/victoria-logs

# Deploy and start
sudo cp victoria-logs.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable victoria-logs
sudo systemctl start victoria-logs
```

## Service Flags Explained

| Flag | Value | Meaning |
|------|-------|---------|
| -storageDataPath | /var/lib/victoria-logs/data | Where data is stored on disk |
| -retentionPeriod | 30d | Delete data older than 30 days |
| -httpListenAddr | :9428 | API port for ingestion and queries |
| -logNewStreams | — | Log when a new stream is detected |
| -logIngestedRows | — | Log ingestion statistics |

## Reserved Fields

| Field | Required | Purpose |
|-------|----------|---------|
| _msg | Yes | Primary log message text |
| _time | Yes | ISO8601 timestamp |
| _stream | Auto | Unique stream identifier |

## LogsQL Quick Reference
```bash
# All logs
curl 'http://localhost:9428/select/logsql/query?query=*&limit=10'

# Filter by field
curl 'http://localhost:9428/select/logsql/query?query=level:ERROR&start=1h'

# Count by service
curl 'http://localhost:9428/select/logsql/query?query=*+|+stats+count()+by+(service)&start=1h'

# Regex search
curl 'http://localhost:9428/select/logsql/query?query=_msg:~"OOM+killer"&start=1h'
```

## Data Storage Structure
```
/var/lib/victoria-logs/data/
├── indexdb/          inverted index (field → log ID mappings)
├── datadb/
│   ├── 2026_03_14/   yesterday's partition
│   └── 2026_03_15/   today's partition (columnar + zstd compressed)
└── metadata/         stream definitions
```

## Verify
```bash
curl http://localhost:9428/health
curl -s http://localhost:9428/metrics | grep rows_ingested
```
