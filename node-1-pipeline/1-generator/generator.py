import json
import time
import os
import re
import sys
import signal
import logging
from datetime import datetime, timezone
from pathlib import Path

INPUT_DIR = "/scripts/logs-original"
OUTPUT_DIR = "/generated-logs"
RATE       = 20

LOG_FILES = [
    ("hpcmlog.json",            "hpcmlog.jsonl"),
    ("monitoring_service.json", "monitoring_service.jsonl"),
    ("syslog.json",             "syslog.jsonl"),
]

_TS_PATTERNS = [
    (re.compile(r'^\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+[+-]\d{4}\]\s*'), ""),
    (re.compile(r'^\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2},\d+\]\s*'), ""),
    (re.compile(r'^\[\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d+\]\s*'), ""),
    (re.compile(r'^\[\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d+\s+[+-]\d{4}\]\s*'), ""),
    (re.compile(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+[+-]\d{2}:\d{2}\s+\S+\s+'), ""),
    (re.compile(r'^\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2},\d+\s*'), ""),
    (re.compile(r'^\d{4}/\d{2}/\d{2}\s+\d{2}:\d{2}:\d{2}\s*'), ""),
    (re.compile(r'^[IWEF]\d{4}\s+\d{2}:\d{2}:\d{2}\.\d+\s+\d+\s+'), ""),
]

_SEVERITY_RE = re.compile(
    r'\b(TRACE|DEBUG|INFO|NOTICE|ERROR|)\b',
    re.IGNORECASE
)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%SZ"
)
log = logging.getLogger("hpc-simulator")


def clean_body(body):
    if not body:
        return body
    for pattern, replacement in _TS_PATTERNS:
        cleaned = pattern.sub(replacement, body, count=1)
        if cleaned != body:
            return cleaned.strip()
    return body.strip()


def extract_severity(src):
    sev = src.get("Severity") or src.get("SeverityText")
    if sev:
        return str(sev).upper()
    m = _SEVERITY_RE.search(src.get("Body", ""))
    if m:
        return m.group(1).upper()
    return None


def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def load_es_export(filepath):
    path = Path(filepath)
    if not path.exists():
        log.error("File not found: %s", filepath)
        return []
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    hits = data.get("hits", {}).get("hits", [])
    entries = [hit["_source"] for hit in hits if "_source" in hit]
    log.info("Loaded %6d entries from %s", len(entries), path.name)
    return entries


def build_record(src):
    record = {
        "@timestamp": now_iso(),
        "Body":       clean_body(src.get("Body", "")),
        "Resource":   src.get("Resource",   {}),
        "Attributes": src.get("Attributes", {}),
    }
    sev = extract_severity(src)
    if sev:
        record["Severity"] = sev
    return record


_running = True

def _shutdown(sig, frame):
    global _running
    log.info("Shutdown signal received — stopping...")
    _running = False

signal.signal(signal.SIGTERM, _shutdown)
signal.signal(signal.SIGINT,  _shutdown)


def main():
    global RATE
    if "--rate" in sys.argv:
        try:
            RATE = int(sys.argv[sys.argv.index("--rate") + 1])
        except (IndexError, ValueError):
            log.warning("Invalid --rate, using default %d", RATE)

    test_mode = "--test" in sys.argv

    log.info("=" * 58)
    log.info("HPC Log Simulator — Robust Replay Edition v2")
    log.info("  Source format : Elasticsearch export (hits.hits._source)")
    log.info("  Input         : %s", INPUT_DIR)
    log.info("  Output        : %s", OUTPUT_DIR)
    log.info("  Rate          : %d logs/sec | Mode: %s",
             RATE, "TEST" if test_mode else "CONTINUOUS")
    log.info("=" * 58)

    os.makedirs(OUTPUT_DIR, exist_ok=True)

    source_data = {}
    for input_file, output_file in LOG_FILES:
        entries = load_es_export(os.path.join(INPUT_DIR, input_file))
        if entries:
            source_data[output_file] = entries
        else:
            log.warning("No entries for %s — skipping", input_file)

    if not source_data:
        log.error("No source data loaded. Exiting.")
        sys.exit(1)

    active = list(source_data.keys())
    log.info("Active streams (%d): %s", len(active), ", ".join(active))

    for out_file in active:
        open(os.path.join(OUTPUT_DIR, out_file), "w").close()
        log.info("Truncated: %s/%s", OUTPUT_DIR, out_file)

    handles   = {f: open(os.path.join(OUTPUT_DIR, f), "a", buffering=1) for f in active}
    positions = {f: 0 for f in active}
    sleep_sec = len(active) / RATE

    if test_mode:
        log.info("TEST MODE: writing 1 record per stream then exiting")
        for out_file in active:
            rec  = build_record(source_data[out_file][0])
            line = json.dumps(rec)
            handles[out_file].write(line + "\n")
            handles[out_file].flush()
            log.info("  -> %s | body: %s", out_file, rec["Body"][:70])
        log.info("Test complete. Check %s", OUTPUT_DIR)
        for fh in handles.values():
            fh.close()
        return

    log.info("Simulator running. Ctrl+C or SIGTERM to stop.")
    total    = 0
    file_idx = 0

    try:
        while _running:
            out_file = active[file_idx % len(active)]
            file_idx += 1
            logs = source_data[out_file]
            pos  = positions[out_file]
            rec  = build_record(logs[pos % len(logs)])
            handles[out_file].write(json.dumps(rec) + "\n")
            positions[out_file] = pos + 1
            total += 1
            if total % 1000 == 0:
                log.info("Generated %d logs | positions: %s",
                         total, {k: positions[k] % len(source_data[k]) for k in active})
            time.sleep(sleep_sec)
    finally:
        for fh in handles.values():
            fh.flush()
            fh.close()
        log.info("Stopped. Total emitted: %d", total)


if __name__ == "__main__":
    main()
