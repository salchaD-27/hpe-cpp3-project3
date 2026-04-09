import json
import time
import os
from datetime import datetime, timezone

LOG_FILES = [
    ("syslog.json",             "syslog.jsonl"),
    ("hpcmlog.json",            "hpcmlog.jsonl"),
    ("monitoring_service.json", "monitoring_service.jsonl"),
]

INPUT_DIR  = "/scripts/logs-original"
OUTPUT_DIR = "/logs/generated"
RATE       = 5

os.makedirs(OUTPUT_DIR, exist_ok=True)

def load_logs(filename):
    path = os.path.join(INPUT_DIR, filename)
    with open(path, "r") as f:
        data = json.load(f)
    hits = data.get("hits", {}).get("hits", [])
    entries = []
    for hit in hits:
        src = hit.get("_source", {})
        entry = {
            "Resource":   src.get("Resource", {}),
            "Body":       src.get("Body", ""),
            "Severity":   src.get("Severity") or src.get("SeverityText", "info"),
            "Attributes": src.get("Attributes", {}),
        }
        entries.append(entry)
    return entries

print("Loading logs...")
all_logs = {}
for input_file, output_file in LOG_FILES:
    logs = load_logs(input_file)
    all_logs[output_file] = logs
    print(f"  Loaded {len(logs)} entries from {input_file}")

print(f"Starting simulation at {RATE} logs/sec per file...")
print("Press Ctrl+C to stop.")

for _, output_file in LOG_FILES:
    path = os.path.join(OUTPUT_DIR, output_file)
    if os.path.exists(path):
        os.remove(path)

handles = {}
for _, output_file in LOG_FILES:
    path = os.path.join(OUTPUT_DIR, output_file)
    handles[output_file] = open(path, "a")

positions = {f: 0 for _, f in LOG_FILES}

try:
    while True:
        for _, output_file in LOG_FILES:
            logs = all_logs[output_file]
            pos  = positions[output_file]
            entry = dict(logs[pos % len(logs)])
            handles[output_file].write(json.dumps(entry) + "\n")
            handles[output_file].flush()
            positions[output_file] = (pos + 1) % len(logs)
        time.sleep(1.0 / RATE)
except KeyboardInterrupt:
    print("Stopping simulator.")
finally:
    for f in handles.values():
        f.close()