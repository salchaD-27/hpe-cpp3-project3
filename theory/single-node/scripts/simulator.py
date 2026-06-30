"""
Log Simulator
Reads original JSON log files and streams entries as JSONL at a fixed rate.
Output files are tailed by Fluent Bit.
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
    return None  # or return "INFO" if you want a default


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