# Pipeline Changes Documentation

## Overview of All Issues Found and Fixed

This document records every problem found in the pipeline from
initial setup to final working state, with full explanation
of what changed, why it was wrong, and how it was fixed.

---

## Issue 1 — Duplicate Kafka Producers (Critical Bug)

### Reported by: Teammate during code review

### What was wrong
```
simulator.py had TWO output paths simultaneously:
  Path 1: producer.send('hpc-logs')  <- direct kafka-python
  Path 2: file_logger.info(json)     <- file for Fluent Bit

Resulting pipeline:
  simulator --> Kafka (Producer 1, WRONG)
  simulator --> file --> Fluent Bit --> Kafka (Producer 2)

Effect: Every log message arrived in Kafka TWICE
```

### How to detect this
```bash
# Rate should be ~20/sec
# If it shows ~40/sec = duplicate producers
R1=$(curl -s http://localhost:9428/metrics | grep rows_ingested | awk '{print $2}')
sleep 10
R2=$(curl -s http://localhost:9428/metrics | grep rows_ingested | awk '{print $2}')
echo $((${R2%.*} - ${R1%.*}))
# 400 = duplicated, 200 = correct
```

### Fix applied

Removed all kafka-python code from simulator.py:
- Removed: `from kafka import KafkaProducer`
- Removed: producer setup block
- Removed: `producer.send('hpc-logs', value=log)`
- Removed: `producer.flush()` and `producer.close()`

Simulator now ONLY writes to log file.
Fluent Bit is the sole Kafka producer.

---

## Issue 2 — Fluent Bit Not Parsing JSON (Structured Fields Lost)

### What was wrong

Initial Fluent Bit config had no Parser in the INPUT block.
Fluent Bit treated each log line as raw text and wrapped it:
```json
{
  "date": 1741234567.0,
  "log": "{\"_msg\": \"Job failed\", \"node\": \"compute-node-08\", ...}"
}
```

All fields were buried inside a string. VictoriaLogs stored
`_msg` as `%{message}` (Logstash template literal).

### Fix applied

Added `Parser hpc_json` to INPUT block.
Added `/etc/fluent-bit/parsers.conf` with:
```ini
[PARSER]
    Name        hpc_json
    Format      json
    Time_Key    _time
    Time_Format %Y-%m-%dT%H:%M:%S.%L%z
    Time_Keep   On
```

Result: All JSON fields expanded directly into record.

---

## Issue 3 — Fluent Bit No Position Tracking (Duplicates on Restart)

### What was wrong

No `DB` setting in INPUT block.
Every Fluent Bit restart re-read log files from beginning.
All historical logs resent as duplicates.

### Fix applied
```ini
[INPUT]
    DB    /var/lib/fluent-bit/tail.db
```

DB file records exact byte offset per watched file.
On restart, Fluent Bit continues from last read position.

---

## Issue 4 — Logstash Output Format Wrong (json_batch vs json)

### What was wrong
```ruby
format => "json_batch"
```

`json_batch` sends records as a JSON array:
`[{...record1...}, {...record2...}]`

VictoriaLogs `/insert/jsonline` expects NDJSON:
```
{...record1...}
{...record2...}
```

Error in VictoriaLogs logs:
`value doesn't contain object; it contains array`

Pipeline appeared to work but 0 records were stored.
Grafana showed nothing.

### Fix applied
```ruby
format => "json"
```

One JSON object per HTTP request, matching NDJSON format.

---

## Issue 5 — Simulator Service File Wrong Path (CHDIR Error)

### What was wrong

After reorganizing repo structure from:
```
victorialogs-eval/simulator/simulator.py
```
to:
```
victorialogs-eval/1_simulator/simulator.py
```

The systemd service file still pointed to old path.
Error: `exit-code 200/CHDIR - No such file or directory`
Simulator restarted 530+ times, log file had 0 lines.

### Fix applied
```ini
WorkingDirectory=/home/shivanshu/victorialogs-eval/1_simulator
ExecStart=.../victorialogs-eval/1_simulator/simulator.py
```

---

## Fluent Bit: Complete Evolution

### Stage 1 — Initial (broken, no parser)
```ini
[INPUT]
    Name    tail
    Path    /var/log/hpc-simulator/*.log
    Tag     hpc.logs

[OUTPUT]
    Name    kafka
    Brokers localhost:9092
    Topics  hpc-logs
```

Problems: No parser, memory-only, no position DB, no compression

### Stage 2 — Parser added (fields now structured)
```ini
[INPUT]
    Name    tail
    Path    /var/log/hpc-simulator/*.log
    Tag     hpc.logs
    Parser  json          <- ADDED
```

Result: Fields now correctly extracted

### Stage 3 — Production config (current)
```ini
[SERVICE]
    Flush            1
    Log_Level        info
    Parsers_File     /etc/fluent-bit/parsers.conf
    storage.path     /var/lib/fluent-bit/storage   <- persistent
    storage.sync     normal
    storage.backlog.mem_limit 50MB

[INPUT]
    Name             tail
    Path             /var/log/hpc-simulator/*.log
    Tag              hpc.logs
    Parser           hpc_json                       <- custom parser
    DB               /var/lib/fluent-bit/tail.db   <- position tracking
    Mem_Buf_Limit    100MB
    Skip_Long_Lines  On
    Refresh_Interval 5

[FILTER]
    Name    modify
    Match   hpc.logs
    Add     pipeline  fluent-bit                    <- metadata
    Add     source    hpc-simulator

[OUTPUT]
    Name             kafka
    Brokers          localhost:9092
    Topics           hpc-logs
    Timestamp_Key    _time
    rdkafka.compression.codec            lz4        <- compression
    rdkafka.batch.num.messages           1000       <- batching
    rdkafka.queue.buffering.max.messages 100000
    rdkafka.linger.ms                    20
    rdkafka.request.required.acks        1
    rdkafka.socket.keepalive.enable      true
```

Improvements:
- Persistent filesystem storage (no data loss on crash)
- Position DB (no duplicates on restart)
- Custom parser with _time field mapping
- lz4 compression (less Kafka disk usage)
- Batch delivery (1000 messages per request)
- Pipeline metadata on every record

---

## Final Verified State
```
Ingestion rate:  200 rows / 10 seconds = 20 logs/sec (1 producer)
VictoriaLogs:    INFO only, zero errors
Data quality:    All fields clean and structured
Pipeline:        simulator -> file -> Fluent Bit -> Kafka ->
                 Logstash -> VictoriaLogs -> Grafana
```
