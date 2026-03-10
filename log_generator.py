import json
import time
import random

levels = ["INFO","WARN","ERROR"]
services = ["scheduler","compute-node","storage","auth"]

logfile = "logs/hpc_logs.json"

while True:
    log = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "level": random.choice(levels),
        "service": random.choice(services),
        "message": "Simulated HPC log event"
    }

    with open(logfile, "a") as f:
        f.write(json.dumps(log) + "\n")
        f.flush()

    time.sleep(1)