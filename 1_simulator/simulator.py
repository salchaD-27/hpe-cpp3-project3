"""
HPC Log Simulator
Generates realistic HPC cluster log events → writes to file only
Fluent Bit reads the file and sends to Kafka (sole producer)

Pipeline: simulator → file → Fluent Bit → Kafka → Logstash → VictoriaLogs
"""

import json
import time
import random
import os
import sys
from datetime import datetime, timezone

# ─── HPC CLUSTER DEFINITION ────

NODES = [f"compute-node-{i:03d}" for i in range(1, 25)]

SERVICES = ["slurmd", "sshd", "kernel", "mpi", "lustre", "ib_core", "nfs", "systemd"]

JOBS = [f"job_{random.randint(10000,99999)}" for _ in range(30)]

TEMPLATES = [
    ("INFO",  "slurmd",  "Job {job} started on {node}, CPUs={cpu}, GPUs={gpu}"),
    ("INFO",  "slurmd",  "Job {job} completed successfully in {dur}s"),
    ("WARN",  "slurmd",  "Job {job} exceeded walltime limit, terminating"),
    ("ERROR", "slurmd",  "Job {job} failed with exit code {code}"),
    ("WARN",  "kernel",  "OOM killer invoked, killed PID {pid} on {node}"),
    ("ERROR", "kernel",  "CPU {cpu_id} machine check error detected"),
    ("ERROR", "ib_core", "InfiniBand port {port} link down unexpectedly"),
    ("INFO",  "ib_core", "InfiniBand ib{port} link up at {speed}Gb/s"),
    ("WARN",  "lustre",  "Lustre OST {ost} I/O error detected"),
    ("WARN",  "lustre",  "Filesystem /scratch at {pct}% capacity"),
    ("INFO",  "mpi",     "MPI job {job} initialized {ranks} ranks"),
    ("ERROR", "mpi",     "MPI collective operation timeout on {node}"),
    ("WARN",  "sshd",    "Failed authentication attempt from {ip}"),
    ("INFO",  "sshd",    "Login accepted for {user} from {ip}"),
    ("WARN",  "nfs",     "NFS /home response time {ms}ms"),
    ("INFO",  "systemd", "Service {svc} started successfully"),
]

# ─── FILE OUTPUT (Fluent Bit reads these) ────

LOG_DIR = '/var/log/hpc-simulator'
os.makedirs(LOG_DIR, exist_ok=True)

log_streams = {
    svc: open(f'{LOG_DIR}/{svc}.log', 'a', buffering=1)
    for svc in SERVICES
}

# ─── LOG GENERATOR ────
def generate():
    level, service, tmpl = random.choice(TEMPLATES)
    node = random.choice(NODES)
    msg  = tmpl.format(
        job     = random.choice(JOBS),
        node    = node,
        cpu     = random.randint(1, 128),
        gpu     = random.randint(0, 8),
        dur     = random.randint(60, 86400),
        code    = random.choice([1, 2, 127, 139]),
        pid     = random.randint(1000, 65535),
        cpu_id  = random.randint(0, 127),
        port    = random.randint(0, 3),
        speed   = random.choice([100, 200, 400]),
        ost     = random.randint(0, 15),
        pct     = random.randint(75, 99),
        ranks   = random.randint(8, 512),
        ip      = f"10.0.{random.randint(0,9)}.{random.randint(1,254)}",
        user    = random.choice(["alice", "bob", "carol", "dave"]),
        ms      = random.randint(100, 5000),
        svc     = random.choice(SERVICES),
    )
    return {
        "_msg":    msg,
        "_time":   datetime.now(timezone.utc).isoformat(),
        "node":    node,
        "service": service,
        "level":   level,
        "job_id":  random.choice(JOBS),
        "cluster": "hpc-cluster-01",
    }

# TEST MODE
if '--test' in sys.argv:
    record = generate()
    print("Generated test record:")
    print(json.dumps(record, indent=2))

    svc = record['service']
    log_streams[svc].write(json.dumps(record) + '\n')
    log_streams[svc].flush()

    print(f"\nWritten to: {LOG_DIR}/{svc}.log")
    print("Wait 3 seconds then check Kafka...")

    for stream in log_streams.values():
        stream.close()
    sys.exit(0)

# ─── MAIN LOOP — batch write ────
RATE  = 20   # logs per second (change to 200, 1000, 5000 for benchmarking)
BATCH = RATE # write once per second in a batch

print(f"Simulator running at {RATE} logs/sec → {LOG_DIR}/{{service}}.log")
print("Fluent Bit is sole Kafka producer (no direct Kafka dependency)")
print("Press Ctrl+C to stop")

count = 0
try:
    while True:
        batch_by_service = {svc: "" for svc in SERVICES}

        for _ in range(BATCH):
            record = generate()
            batch_by_service[record['service']] += json.dumps(record) + '\n'
            count += 1

        # Write each service batch to its own file — one write() call per service
        for svc, batch in batch_by_service.items():
            if batch:
                log_streams[svc].write(batch)

        if count % 1000 == 0:
            print(f"Generated {count} logs")

        time.sleep(1.0)

except KeyboardInterrupt:
    print(f"\nStopped. Total logs generated: {count}")
    for stream in log_streams.values():
        stream.close()
