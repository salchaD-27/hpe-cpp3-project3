# HPC Log Simulator

Generates realistic synthetic HPC cluster log events and sends them to Apache Kafka at 20 logs per second.

## What It Does

- Simulates 24 compute nodes (compute-node-001 to compute-node-024)
- Simulates 8 HPC services: slurmd, sshd, kernel, mpi, lustre, ib_core, nfs, systemd
- Generates 16 realistic log templates (job start/fail, OOM kill, InfiniBand errors, etc.)
- Sends each log directly to Kafka topic `hpc-logs`
- Also writes each log to `/var/log/hpc-simulator/hpc-cluster.log` for Fluent Bit

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
```bash
# Create Python virtual environment
python3 -m venv ~/hpc-venv
source ~/hpc-venv/bin/activate
pip install kafka-python
```

## Run Directly (for testing)
```bash
source ~/hpc-venv/bin/activate
python3 simulator.py
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

## Verify 
```bash
# Check log file is growing
watch -n 2 wc -l /var/log/hpc-simulator/hpc-cluster.log

# Check Kafka is receiving messages
/opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic hpc-logs --max-messages 3 2>/dev/null
```

## Why Systemd Service Over Direct Script

| | Direct Script | Systemd Service |
|---|---|---|
| Survives terminal close | ❌ | ✅ |
| Auto-starts on boot | ❌ | ✅ |
| Restarts on crash | ❌ | ✅ |
| Consistent Python env | ❌ | ✅ |
