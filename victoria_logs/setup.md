# VictoriaLogs Setup and Integration with Logstash

## HPE CPP-3 Project – Log and Event Management Evaluation

## 1. Overview

VictoriaLogs is a high-performance log storage engine designed for observability pipelines. It is part of the VictoriaMetrics ecosystem and provides efficient log ingestion, compression, indexing, and querying capabilities.

In this project, VictoriaLogs was evaluated as a potential alternative to traditional log storage systems such as OpenSearch for HPC-scale log ingestion.

The complete pipeline implemented for the evaluation was:

Python Log Simulator → Fluent Bit → Kafka → Logstash → VictoriaLogs → Grafana

VictoriaLogs serves as the central log storage and query engine in this architecture.

---

# 2. System Environment

| Component    | Version    |
| ------------ | ---------- |
| OS           | Arch Linux |
| Kafka        | KRaft Mode |
| Logstash     | 8.x        |
| VictoriaLogs | v1.48.0    |
| Java         | OpenJDK 17 |

---

# 3. Installing VictoriaLogs

The following options are available:

* To run pre-built binaries
* To run Docker image
* To run in Kubernetes with Helm charts
* To run in Kubernetes with VictoriaMetrics Operator (VLSingle / VLCluster CRDs)
* To build VictoriaLogs from source code

### Download Pre-built Binary

```bash
curl -L -O https://github.com/VictoriaMetrics/VictoriaLogs/releases/download/v1.48.0/victoria-logs-linux-amd64-v1.48.0.tar.gz
tar xzf victoria-logs-linux-amd64-v1.48.0.tar.gz
./victoria-logs-prod -storageDataPath=victoria-logs-data
```

After execution the following binaries are available:

```
victoria-logs-prod
victoria-logs
```

The production binary `victoria-logs-prod` was used.

---

# 4. Directory Structure

A dedicated directory was created for persistent storage.

```
hpe-cpp3-project3/
│
├── kafka/
├── fluentbit/
├── logstash/
├── victorialogs/
│   └── victoria-logs-data/
└── log_generator.py
```

---

# 5. Running VictoriaLogs

VictoriaLogs requires a storage path where log data will be persisted.

### Run Command

```bash
./victoria-logs-prod -storageDataPath=victoria_logs/victoria-logs-data
```

### Startup Output

```
starting VictoriaLogs at "[:9428]"
started server at http://0.0.0.0:9428/
```

VictoriaLogs exposes an HTTP API on port:

```
9428
```

### Verify Service

```
curl http://localhost:9428/health
```

Expected output:

```
OK
```

---

# 6. Running VictoriaLogs as Background Service(Optional)

For long running pipelines the service was started using:

```bash
nohup ./victoria-logs-prod \
-storageDataPath=victoria_logs/victoria-logs-data &
```

Check process:

```bash
ps aux | grep victoria
```

---

# 7. Logstash Integration

Logstash consumes logs from Kafka and forwards them to VictoriaLogs.

The integration uses the **Elasticsearch Bulk API compatibility layer** implemented by VictoriaLogs.

This approach is recommended because:

* Logstash natively supports Elasticsearch outputs
* VictoriaLogs implements the same ingestion API
* Supports high throughput bulk ingestion

---

# 8. Log Ingestion Flow

```
Python Log Generator
        ↓
Fluent Bit
        ↓
Kafka Topic (logs)
        ↓
Logstash Consumer
        ↓
VictoriaLogs
```

Logs are inserted using the endpoint:

```
/insert/elasticsearch/_bulk
```

---

# 9. Debugging Issues Encountered

Several integration issues occurred during the setup.

---

# Issue 1: Hostname Resolution Failure

### Error

```
victorialogs: Name or service not known
```

### Cause

Logstash attempted to connect using hostname:

```
http://victorialogs:9428
```

But VictoriaLogs was running locally.

### Fix

Updated configuration:

```
http://localhost:9428
```

---

# Issue 2: Invalid Timestamp (1970)

### Error

```
skipping log entry with too small timestamp=1970-01-01
```

### Cause

Logstash was not properly parsing the timestamp field.

### Fix

Added date filter:

```
date {
 match => ["timestamp", "yyyy-MM-dd HH:mm:ss"]
 target => "@timestamp"
}
```

---

# Issue 3: JSON Array Instead of Object

### Error

```
value doesn't contain object; it contains array
```

### Cause

Logs were sent to endpoint:

```
/insert/jsonline
```

but Logstash `json_batch` format wraps logs in arrays.

Example payload:

```
[
  {...},
  {...}
]
```

The `/jsonline` endpoint expects newline-separated JSON objects.

### Fix

Switched to the Elasticsearch Bulk endpoint.

```
/insert/elasticsearch/_bulk
```

---

# Issue 4: Logs Ignored Because of Debug Mode

### Error

```
ignoring log entry because of debug arg
```

### Cause

Requests contained parameter:

```
debug=1
```

which prevents logs from being stored.

### Fix

Removed debug parameter from ingestion URL.

---

# 11. Validation

Logs were verified using LogsQL queries.

Example query:

```
*
```

Example HTTP query:

```
curl http://localhost:9428/select/logsql/query \
-d 'query=*'
```

---

# 12. Observability Metrics

VictoriaLogs exposes Prometheus metrics at:

```
http://localhost:9428/metrics
```

Key metrics:

```
vl_rows_ingested_total
vl_active_streams
vl_storage_size_bytes
```

These metrics are used to evaluate:

* ingestion throughput
* resource utilization
* storage efficiency

---

# 13. Conclusion

VictoriaLogs successfully integrated into the HPC observability pipeline and demonstrated:

* efficient bulk log ingestion
* compatibility with existing Elasticsearch tooling
* simplified deployment compared to traditional log management systems

The debugging process highlighted the importance of:

* correct ingestion endpoints
* timestamp normalization
* correct JSON formats for ingestion APIs.

VictoriaLogs proved to be a lightweight yet powerful log storage engine suitable for high-throughput log pipelines.