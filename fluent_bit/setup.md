# Fluent Bit Setup Guide

This guide explains how to run a simple log ingestion pipeline using **Fluent Bit**, a Python log generator, and Docker. It simulates logs from HPC services and streams them through Fluent Bit.

---

## Project Structure

hpe-cpp3-project3/
│
├── log_generator.py
├── logs/
│ └── hpc_logs.json
│
└── fluent_bit/
    ├── conf.yaml
    └── parsers.conf


---

## Prerequisites

Make sure the following tools are installed on your system:

* Python 3
* Docker

Check installation:

```bash
python --version
docker --version
```

## Step 1: Clone or Download the Project

```bash
git clone <repo-url>
cd hpe-cpp3-project3
```
Create the logs directory if it doesn't exist:
```bash
mkdir -p logs
```
## Files Included and Description :

1. The Python script simulates HPC-style logs and continuously writes JSON log entries.

`log_generator.py` : This script writes one log entry every second.

2. `fluent_bit/conf.yaml` : Fluent Bit Configuration

3. `fluent_bit/parsers.conf` : Fluent Bit Parser Configuration

## Step 2: Start Fluent Bit (Docker)

Run Fluent Bit using the official container image:

```bash
docker run -it \
-p 2020:2020 \
-v $(pwd)/fluent_bit/conf.yaml:/fluent-bit/etc/fluent-bit.yaml \
-v $(pwd)/fluent_bit/parsers.conf:/fluent-bit/etc/parsers.conf \
-v $(pwd)/logs:/logs \
cr.fluentbit.io/fluent/fluent-bit \
--config=/fluent-bit/etc/fluent-bit.yaml
```

This command:

* mounts the Fluent Bit config

* mounts the parser file

* mounts the logs directory

* exposes the metrics API on port 2020


## Step 3: Start the Log Generator

Open a second terminal and run:

```bash
python log_generator.py
```

The script will continuously append logs to:

```bash
logs/hpc_logs.json
```

## Step 4: Observe Fluent Bit Output

Fluent Bit will read new log entries in real time and output them to the console.

Example output:

```bash
{"timestamp":"2026-03-10 08:34:18","level":"ERROR","service":"storage","message":"Simulated HPC log event"}
{"timestamp":"2026-03-10 08:34:19","level":"WARN","service":"scheduler","message":"Simulated HPC log event"}
```

## Fluent Bit Metrics Endpoint

Fluent Bit exposes a metrics API that can be accessed at:

`http://localhost:2020/api/v1/metrics`

This endpoint provides runtime statistics such as:

* processed records

* input/output metrics

* memory usage

## Running the Setup on Another System

Anyone can reproduce this setup by following these steps:

1. Install Python and Docker

2. Clone the repository

3. Create the logs directory

4. Start Fluent Bit container

5. Run the Python log generator

Once running, Fluent Bit will automatically ingest logs written to the file and stream them to the configured output.

## Summary

This setup demonstrates a basic log ingestion pipeline:

```bash
Python Log Generator
        ↓
Log File (JSON)
        ↓
Fluent Bit (tail input)
        ↓
Console Output
```

This architecture is similar to how logs are collected in distributed systems and cluster environments.

## TO larn more about fluent_bit :

simulator : `https://core.calyptia.com/`