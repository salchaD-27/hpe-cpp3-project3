# const fs = require('fs');
# const path = require('path');

# const OUTPUT_DIR = '/logs-generated';

# // Synthetic log data
# const LOG_TYPES = ['hpcmlog', 'monitoring_service', 'syslog'];
# const HOSTS = ['leader1', 'leader2', 'leader3', 'padma', 'worker1', 'worker2'];
# const SERVICES = {
#     hpcmlog: ['glusterd', 'cli', 'data-brick_ctdb', 'cmuserver-0', 'sensormon_v2'],
#     monitoring_service: ['kafka', 'opensearch', 'prometheus', 'zookeeper'],
#     syslog: ['systemd', 'sudo', 'cron', 'sshd', 'kernel']
# };
# const SEVERITIES = ['INFO', 'WARN', 'ERROR', 'DEBUG'];

# // Ensure output directory exists
# if (!fs.existsSync(OUTPUT_DIR)) {
#     fs.mkdirSync(OUTPUT_DIR, { recursive: true });
# }

# let counters = {
#     hpcmlog: 0,
#     monitoring_service: 0,
#     syslog: 0
# };

# console.log(`[${new Date().toISOString()}] Synthetic log generator started`);
# console.log(`Output directory: ${OUTPUT_DIR}`);
# console.log(`Generating logs for: ${LOG_TYPES.join(', ')}`);

# function generateLogForType(logType) {
#     const host = HOSTS[Math.floor(Math.random() * HOSTS.length)];
#     const service = SERVICES[logType][Math.floor(Math.random() * SERVICES[logType].length)];
#     const severity = SEVERITIES[Math.floor(Math.random() * SEVERITIES.length)];
    
#     const logEntry = {
#         "@timestamp": new Date().toISOString(),
#         "Body": `[${new Date().toISOString()}] ${severity}: [${service}] Operation from ${host}`,
#         "Severity": severity,
#         "Resource": {
#             "host.name": host,
#             "service.name": service
#         },
#         "Attributes": {
#             "pid": Math.floor(Math.random() * 10000),
#             "counter": ++counters[logType]
#         },
#         "source_file": `/logs/${logType}.log`
#     };
    
#     const filePath = path.join(OUTPUT_DIR, `${logType}.jsonl`);
#     fs.appendFileSync(filePath, JSON.stringify(logEntry) + '\n');
#     return logEntry;
# }

# let totalGenerated = 0;

# // Generate logs at 5 per second per type (15 total/sec)
# setInterval(() => {
#     for (const logType of LOG_TYPES) {
#         generateLogForType(logType);
#         totalGenerated++;
#     }
    
#     if (totalGenerated % 30 === 0) {
#         console.log(`[${new Date().toISOString()}] Generated ${totalGenerated} total logs`);
#     }
# }, 200);

# // Keep process alive
# process.stdin.resume();


"""
Log Simulator
Reads original JSON log files and streams entries as JSONL at a fixed rate.
Output files are tailed by Fluent Bit.

Identical to the single-node simulator — no changes needed.
"""

import json
import time
import os
import re

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
INPUT_DIR  = "/scripts/logs-original"
OUTPUT_DIR = "/generated-logs"
RATE       = 20          # logs per second per file

LOG_FILES = [
    ("hpcmlog.json",            "hpcmlog.jsonl"),
    ("monitoring_service.json", "monitoring_service.jsonl"),
    ("syslog.json",             "syslog.jsonl"),
]

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
SEVERITY_REGEX = re.compile(
    r"\b(TRACE|DEBUG|INFO|WARN|WARNING|ERROR|FATAL)\b",
    re.IGNORECASE
)

def extract_severity(src: dict) -> str | None:
    """Determine severity from structured fields or fallback to parsing Body."""

    # 1. Structured fields
    severity = src.get("Severity") or src.get("SeverityText")
    if severity:
        return severity.upper()

    # 2. Try extracting from Body
    body = src.get("Body", "")
    match = SEVERITY_REGEX.search(body)
    if match:
        return match.group(1).upper()

    # 3. No severity found
    return None


def load_logs(filename: str) -> list[dict]:
    """Load log entries from the original JSON export (Elasticsearch hits format)."""
    path = os.path.join(INPUT_DIR, filename)
    with open(path) as f:
        data = json.load(f)

    hits = data.get("hits", {}).get("hits", [])
    entries = []

    for hit in hits:
        src = hit.get("_source", {})

        severity = extract_severity(src)

        entry = {
            "Resource":   src.get("Resource", {}),
            "Body":       src.get("Body", ""),
            "Attributes": src.get("Attributes", {}),
        }

        # Only include Severity if we found one
        if severity:
            entry["Severity"] = severity

        entries.append(entry)

    return entries


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
os.makedirs(OUTPUT_DIR, exist_ok=True)

print("Loading logs...")
all_logs: dict[str, list] = {}
for input_file, output_file in LOG_FILES:
    logs = load_logs(input_file)
    all_logs[output_file] = logs
    print(f"  {input_file}: {len(logs)} entries")

print(f"\nSimulating at {RATE} logs/sec per file — Ctrl+C to stop\n")

# Truncate output files on start so Fluent Bit reads from head each run
for _, output_file in LOG_FILES:
    open(os.path.join(OUTPUT_DIR, output_file), "w").close()

handles = {
    output_file: open(os.path.join(OUTPUT_DIR, output_file), "a")
    for _, output_file in LOG_FILES
}
positions = {output_file: 0 for _, output_file in LOG_FILES}

try:
    while True:
        for _, output_file in LOG_FILES:
            logs = all_logs[output_file]
            pos  = positions[output_file]

            entry = dict(logs[pos % len(logs)])
            handles[output_file].write(json.dumps(entry) + "\n")
            handles[output_file].flush()

            positions[output_file] = pos + 1

        time.sleep(1.0 / RATE)

except KeyboardInterrupt:
    print("Stopping simulator.")

finally:
    for fh in handles.values():
        fh.close()