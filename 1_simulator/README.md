# HPC Log Simulator

Generates realistic synthetic HPC cluster log events and writes them to **per-service log files**. Fluent Bit tails all service files and forwards events to Kafka.

## Pipeline Role
```
simulator.py → /var/log/hpc-simulator/{service}.log (×8) → Fluent Bit → Kafka
```

The simulator has **no direct Kafka dependency**.  
Fluent Bit is the **sole Kafka producer**.

---

## What It Does

- Simulates **24 compute nodes** (`compute-node-001` → `compute-node-024`)
- Simulates **8 HPC services**: `slurmd`, `sshd`, `kernel`, `mpi`, `lustre`, `ib_core`, `nfs`, `systemd`
- Generates **16 realistic log templates** — job start/fail, OOM kill, InfiniBand errors, Lustre I/O warnings, MPI timeouts, and more
- Writes logs in **batches to per-service files** (`/var/log/hpc-simulator/<service>.log`)
- Default rate: **20 logs/second** (configurable via `RATE` constant)

### Why Per-Service Files?

Each service writes to its own log file. This mirrors how real HPC nodes emitlogs — `sshd` writes to its own journal, `slurmd` to its own, and so on. 
It also lets Fluent Bit track position **independently per service** via its DB file, so a restart never re-reads events from an already-processed service.

---

## Sample Log Event
```json
{
  "_msg":    "Job job_87892 failed with exit code 2",
  "_time":   "2026-03-15T06:13:03.054822+00:00",
  "node":    "compute-node-024",
  "service": "slurmd",
  "level":   "ERROR",
  "job_id":  "job_42243",
  "cluster": "hpc-cluster-01"
}
```

All fields are top-level JSON keys — no nested objects — so VictoriaLogs can index them directly without a custom field extractor.

---


### Quick Validation (--test mode)

Generates exactly one log event, writes it to the appropriate service file,prints the JSON to stdout, and exits. Use this to confirm the file path and JSON structure before starting Fluent Bit.

```bash
python3 simulator.py --test
```


## Verify It Is Working
```bash
# List all service log files (should see 8 files)
ls -lh /var/log/hpc-simulator/

# Watch a specific service file grow in real time
tail -f /var/log/hpc-simulator/slurmd.log

# Count lines across all files after 10 seconds (expect ~200 new lines)
sleep 10 && wc -l /var/log/hpc-simulator/*.log

# Confirm JSON is valid on a sample line
tail -1 /var/log/hpc-simulator/kernel.log | python3 -m json.tool

# Confirm Kafka is receiving events via Fluent Bit
/opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic hpc-logs --max-messages 5 2>/dev/null
```

---

## Why Systemd Service Over Direct Script

| Capability              | Direct Script | Systemd Service |
|-------------------------|:-------------:|:---------------:|
| Survives terminal close | ❌            | ✅              |
| Auto-starts on boot     | ❌            | ✅              |
| Restarts on crash       | ❌            | ✅              |
| Consistent Python env   | ❌            | ✅              |
| Logs visible via journalctl | ❌        | ✅              |

---

## Important — No Direct Kafka Dependency

The simulator writes **only** to log files.  
Fluent Bit is the **sole Kafka producer**.

**Why this matters:** Having the simulator send directly to Kafka while Fluent Bit also reads the same log file creates two producers on the same Kafka topic.
Every log event arrives twice, causing:
- Duplicate records in VictoriaLogs
- 2× the expected ingestion rate (detectable via VictoriaLogs metrics)
- Inconsistent message ordering in partitions

This was an architectural bug identified during early pipeline testing and was resolved by removing the direct Kafka producer path entirely.

---

## Scaling the Ingestion Rate

Change the `RATE` constant in `simulator.py` for benchmarking experiments:
```python
RATE = 20      # default — baseline evaluation
RATE = 200     # medium load test
RATE = 1000    # high load test
RATE = 5000    # stress test
```

After changing `RATE`, restart the systemd service:
```bash
sudo systemctl restart hpc-simulator
```

---

## Log Files Reference

| Service   | Log File Path                              |
|-----------|--------------------------------------------|
| slurmd    | `/var/log/hpc-simulator/slurmd.log`        |
| sshd      | `/var/log/hpc-simulator/sshd.log`          |
| kernel    | `/var/log/hpc-simulator/kernel.log`        |
| mpi       | `/var/log/hpc-simulator/mpi.log`           |
| lustre    | `/var/log/hpc-simulator/lustre.log`        |
| ib_core   | `/var/log/hpc-simulator/ib_core.log`       |
| nfs       | `/var/log/hpc-simulator/nfs.log`           |
| systemd   | `/var/log/hpc-simulator/systemd.log`       |
