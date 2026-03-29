# Fluent Bit — Log Collector

Fluent Bit tails all per-service simulator log files using inotify, parses each line with a custom JSON parser, enriches events with pipeline metadata,
and forwards them to Apache Kafka with production-grade performance tuning.

## Role in Pipeline
```
/var/log/hpc-simulator/{service}.log  (×8 files)
                   ↓
              Fluent Bit
       (tail + inotify + hpc_json parser)
                   ↓
         [FILTER] add pipeline metadata
                   ↓
         Kafka topic: hpc-logs
         (lz4 compressed, batched)
```

Fluent Bit is the **sole Kafka producer** in this pipeline.  
The simulator writes only to log files and has no Kafka dependency.

---

## Installation
```bash
# Official install script
curl https://raw.githubusercontent.com/fluent/fluent-bit/master/install.sh | sh

# Add binary to PATH
echo 'export PATH=$PATH:/opt/fluent-bit/bin' >> ~/.bashrc
source ~/.bashrc

# Verify
fluent-bit --version

# Create storage and DB directories
sudo mkdir -p /var/lib/fluent-bit/storage
sudo chown -R fluent-bit:fluent-bit /var/lib/fluent-bit
```

---

## Configuration Files

Fluent Bit requires **two** config files for this setup.

### `/etc/fluent-bit/parsers.conf` — Custom JSON Parser
```ini
[PARSER]
    Name         hpc_json
    Format       json
    Time_Key     _time
    Time_Format  %Y-%m-%dT%H:%M:%S.%L%z
    Time_Keep    On
```

**Why a custom parser instead of the built-in `json` parser?**

The built-in `json` parser does not know which field holds the event timestamp.
It stamps every record with the wall-clock time Fluent Bit *read* the line —
not the time the simulator *generated* it. Under any I/O delay or backlog
replay, this produces incorrect timestamps in VictoriaLogs.

The `hpc_json` parser explicitly maps `_time` as the timestamp key using the
ISO 8601 format the simulator emits (`%Y-%m-%dT%H:%M:%S.%L%z`). `Time_Keep On`
preserves `_time` as a regular field in the event *in addition* to using it as
the record timestamp, so downstream systems (Logstash, VictoriaLogs) always
see it.

---

## Verify It Is Working
```bash
# 1. Check for startup errors
sudo journalctl -u fluent-bit --no-pager -n 30

# 2. Health check endpoint
curl -s http://localhost:2020/api/v1/health

# 3. Confirm all 8 log files are being tailed
# Look for 8 lines containing inotify_fs_add
sudo journalctl -u fluent-bit --no-pager | grep inotify_fs_add

# 4. Check ingestion metrics (records_total should increase every second)
curl -s http://localhost:2020/api/v1/metrics | grep records_total

# 5. Confirm events are reaching Kafka
/opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic hpc-logs --max-messages 5 2>/dev/null

# 6. Confirm the pipeline and source fields are present
/opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic hpc-logs --max-messages 1 2>/dev/null | python3 -m json.tool
# Expected: "pipeline": "fluent-bit" and "source": "hpc-simulator" in output

# 7. Confirm position DB exists and is non-zero (means offsets are being tracked)
ls -lh /var/lib/fluent-bit/tail.db
```

### Key Log Lines That Confirm Correct Operation
```
# File being tailed
inotify_fs_add(): name=/var/log/hpc-simulator/slurmd.log ...

# Kafka connection established
[kafka] brokers='localhost:9092' topics='hpc-logs'

# Events flowing (appears every flush interval)
[output:kafka] hpc.* > records=20 bytes=...
```
---
