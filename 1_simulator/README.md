
# HPC Log Simulator

Generates realistic synthetic HPC cluster log events and writes them to a log file. Fluent Bit reads the file and forwards to Kafka.

## Pipeline Role
```
simulator.py --> /var/log/hpc-simulator/hpc-cluster.log --> Fluent Bit --> Kafka
```

The simulator has NO direct Kafka dependency.
Fluent Bit is the sole Kafka producer.

## What It Does

- Simulates 24 compute nodes (compute-node-001 to compute-node-024)
- Simulates 8 HPC services: slurmd, sshd, kernel, mpi, lustre, ib_core, nfs, systemd
- Generates 16 realistic log templates (job start/fail, OOM kill, InfiniBand errors, etc.)
- Writes logs in batches to `/var/log/hpc-simulator/hpc-cluster.log`
- Rate: 20 logs/second (configurable via RATE constant)

## Sample Log Event
```json
{
  "_msg": "Job job_87892 failed with exit code 2",
  "_time": "2026-03-15T06:13:03.054822+00:00",
  "node": "compute-node-024",
  "service": "slurmd",
  "level": "ERROR",
  "job_id": "job_42243",
  "cluster": "hpc-cluster-01"
}
```

## Prerequisites

No third-party packages required. Uses Python standard library only.
```bash
# Python 3.6+ required 
python3 --version

# Create log directory
sudo mkdir -p /var/log/hpc-simulator
sudo chmod 777 /var/log/hpc-simulator
```

## Run Directly (for testing)
```bash
python3 simulator.py
# Press Ctrl+C to stop
```

## Run as Systemd Service (recommended)
```bash
# Copy service file
sudo cp hpc-simulator.service /etc/systemd/system/

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable hpc-simulator
sudo systemctl start hpc-simulator

# Check status
sudo systemctl status hpc-simulator --no-pager
```

## Verify It Is Working
```bash
# Check log file is growing (number should increase every second)
sleep 5 && wc -l /var/log/hpc-simulator/hpc-cluster.log
sleep 5 && wc -l /var/log/hpc-simulator/hpc-cluster.log

# Check last 3 log lines
tail -3 /var/log/hpc-simulator/hpc-cluster.log

# Check Kafka is receiving messages via Fluent Bit
/opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic hpc-logs --max-messages 3 2>/dev/null
```

## Why Systemd Service Over Direct Script

|                        | Direct Script | Systemd Service |
|------------------------|---------------|-----------------|
| Survives terminal close | ❌            | ✅              |
| Auto-starts on boot     | ❌            | ✅              |
| Restarts on crash       | ❌            | ✅              |
| Consistent Python env   | ❌            | ✅              |

## Important — No Direct Kafka Dependency

The simulator writes ONLY to the log file.
Fluent Bit is the sole Kafka producer.

**Why this matters:** Having the simulator send directly to Kafka while Fluent Bit also reads the same log file creates two producers on the same Kafka topic. 
Every log message arrives twice causing:
- Duplicate records in VictoriaLogs
- 2x expected ingestion rate (detectable via metrics)
- Inconsistent message ordering

## Scaling the Rate

Change the `RATE` constant in `simulator.py` for benchmarking:
```python
RATE = 20      # default — 20 logs/sec
RATE = 200     # medium load test
RATE = 1000    # high load test
RATE = 5000    # stress test
```
