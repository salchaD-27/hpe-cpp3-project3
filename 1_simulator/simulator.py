#!/usr/bin/env python3
"""
HPC Log Simulator
Generates realistic HPC cluster log events → sends to Kafka topic hpc-logs
"""
from kafka import KafkaProducer
import json, random, time, sys
from datetime import datetime, timezone
import os, logging
os.makedirs('/var/log/hpc-simulator', exist_ok=True)
file_logger = logging.getLogger('hpc')
handler = logging.FileHandler('/var/log/hpc-simulator/hpc-cluster.log')
file_logger.addHandler(handler)
file_logger.setLevel(logging.INFO)
# ── HPC Environment ───────────────────────────────────────────
NODES    = [f"compute-node-{i:03d}" for i in range(1, 25)]
SERVICES = ["slurmd","sshd","kernel","mpi","lustre","ib_core","nfs","systemd"]
JOBS     = [f"job_{random.randint(10000,99999)}" for _ in range(30)]

TEMPLATES = [
    # Scheduler
    ("INFO",  "slurmd",  "Job {job} started on {node}, CPUs={cpu}, GPUs={gpu}"),
    ("INFO",  "slurmd",  "Job {job} completed successfully in {dur}s"),
    ("WARN",  "slurmd",  "Job {job} exceeded walltime limit, terminating"),
    ("ERROR", "slurmd",  "Job {job} failed with exit code {code}"),
    # Kernel
    ("WARN",  "kernel",  "OOM killer invoked, killed PID {pid} on {node}"),
    ("ERROR", "kernel",  "CPU {cpu_id} machine check error detected"),
    ("INFO",  "kernel",  "NUMA node {numa} memory at {pct}%"),
    # Network
    ("INFO",  "ib_core", "InfiniBand ib{port} link up at {speed}Gb/s"),
    ("ERROR", "ib_core", "InfiniBand port {port} link down unexpectedly"),
    ("WARN",  "mpi",     "MPI rank {rank} communication timeout after {ms}ms"),
    # Storage
    ("WARN",  "lustre",  "Filesystem /scratch at {pct}% capacity"),
    ("ERROR", "lustre",  "Lustre OST {ost} I/O error detected"),
    ("INFO",  "nfs",     "NFS /home response time {ms}ms"),
    # Auth
    ("INFO",  "sshd",    "Login accepted for {user} from {ip}"),
    ("WARN",  "sshd",    "Failed authentication attempt from {ip}"),
    ("ERROR", "sshd",    "Too many auth failures from {ip}, blocking"),
]

def generate():
    level, svc, tmpl = random.choice(TEMPLATES)
    node = random.choice(NODES)
    return {
        "_msg": tmpl.format(
            job    = random.choice(JOBS),
            node   = node,
            cpu    = random.randint(1, 128),
            gpu    = random.randint(0, 8),
            dur    = random.randint(60, 86400),
            code   = random.choice([1, 2, 127, 139]),
            pid    = random.randint(1000, 65535),
            cpu_id = random.randint(0, 127),
            numa   = random.randint(0, 3),
            pct    = random.randint(60, 99),
            port   = random.randint(0, 3),
            speed  = random.choice([100, 200, 400]),
            rank   = random.randint(0, 511),
            ms     = random.randint(100, 5000),
            ost    = random.randint(0, 15),
            user   = random.choice(["alice","bob","carol","research01","admin"]),
            ip     = f"10.0.{random.randint(1,10)}.{random.randint(1,254)}",
        ),
        "_time":   datetime.now(timezone.utc).isoformat(),
        "node":    node,
        "service": svc,
        "level":   level,
        "job_id":  random.choice(JOBS),
        "cluster": "hpc-cluster-01",
    }
# ── Connect to Kafka ─────────────────────────────────────────
print("Connecting to Kafka...")
try:
    producer = KafkaProducer(
        bootstrap_servers=['localhost:9092'],
        value_serializer=lambda v: json.dumps(v).encode('utf-8'),
        acks='all',
        retries=3
    )
    print("Connected to Kafka OK")
except Exception as e:
    print(f"Kafka connection failed: {e}")
    sys.exit(1)
RATE  = 20   # logs per second
count = 0
print(f"Simulator running at {RATE} logs/sec — Ctrl+C to stop")
print("-" * 60)

while True:
    try:
        log = generate()
        producer.send('hpc-logs', value=log)
        file_logger.info(json.dumps(log))
        count += 1
        if count % 100 == 0:
            print(f"[{count:6d}] [{log['level']:5s}] {log['node']} | {log['_msg'][:55]}")
        time.sleep(1.0 / RATE)
    except KeyboardInterrupt:
        print(f"\nStopped. Total logs sent: {count}")
        producer.flush()
        sys.exit(0)
    except Exception as e:
        print(f"Error: {e}")
        time.sleep(1)


