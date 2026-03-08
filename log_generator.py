import json
import time
import random

levels = ["INFO","WARN","ERROR"]

services = ["scheduler","compute-node","storage","auth"]

while True:
    log = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "level": random.choice(levels),
        "service": random.choice(services),
        "message": "Simulated HPC log event"
    }

    print(json.dumps(log), flush=True)

    time.sleep(1)