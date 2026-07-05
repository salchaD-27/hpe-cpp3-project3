#!/usr/bin/env python3
"""
send.py
-------
Sends hardware inventory data to VictoriaLogs, one component type per run.
Tracks what has already been sent to avoid duplicates.

Usage:
  python send.py           # sends next pending type
  python send.py --status  # shows what has/hasn't been sent
  python send.py --dry-run # preview without sending

How it works:
  - Reads inventory-data-bardpeak001.json
  - Each run sends one component type (node, cpu, disk, dimm, interface, gpu, nic)
  - Saves sent types to sent_types.txt to avoid sending again
  - Each record gets the current timestamp so you can query by date in VictoriaLogs
"""

import json
import argparse
import urllib.request
import urllib.error
import sys
import os
from datetime import datetime, timezone

# =============================================================================
# CONFIG — change these if needed
# =============================================================================
VLINSERT_URL   = "http://localhost:9429/insert/jsonline"
INVENTORY_FILE = "inventory-data-bardpeak001.json"
SENT_FILE      = "sent_types.txt"
NODE_NAME      = "bardpeak001"

# Order in which component types will be sent, one per run
TYPES_ORDER = ["node", "cpu", "disk", "dimm", "interface", "gpu", "nic"]

# =============================================================================
# HELPERS
# =============================================================================

def load_sent():
    """Load list of already-sent component types."""
    if not os.path.exists(SENT_FILE):
        return []
    with open(SENT_FILE) as f:
        return [line.strip() for line in f if line.strip()]


def mark_sent(component_type):
    """Append a component type to the sent file."""
    with open(SENT_FILE, "a") as f:
        f.write(component_type + "\n")


def print_status(sent):
    """Show which types have been sent and which are pending."""
    print("\nStatus:")
    print(f"  {'Type':<12} {'Status'}")
    print(f"  {'-'*11} {'-'*10}")
    for t in TYPES_ORDER:
        status = "SENT" if t in sent else "PENDING"
        print(f"  {t:<12} {status}")
    pending = [t for t in TYPES_ORDER if t not in sent]
    print(f"\n  {len(sent)} sent, {len(pending)} pending\n")


def build_record(item):
    """Build a VictoriaLogs record from a component, preserving original field names."""
    record = {}
    record["_time"]      = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    record["_msg"]       = f"{item['type']} | {item['name']}"
    record["log_source"] = "inventory"
    record["name"]       = item["name"]
    record["type"]       = item["type"]
    record["manufacturer"] = item.get("manufacturer", "Unknown")
    record["id"]         = item.get("id", "")

    if "serialNumber" in item:
        record["serialNumber"] = item["serialNumber"]
    if "partNumber" in item:
        record["partNumber"] = item["partNumber"]

    # flatten properties with dot notation, preserving exact key names
    def flatten(obj, prefix):
        for k, v in obj.items():
            key = f"{prefix}.{k}"
            if isinstance(v, dict):
                flatten(v, key)
            elif isinstance(v, list):
                record[key] = json.dumps(v)
            else:
                record[key] = str(v) if v is not None else ""

    flatten(item.get("properties", {}), "properties")
    return record


def send(records, dry_run=False):
    """POST records to VictoriaLogs."""
    ndjson = "\n".join(json.dumps(r) for r in records) + "\n"
    url = (
        f"{VLINSERT_URL}"
        f"?_stream_fields=log_source"
        f"&_msg_field=_msg"
        f"&_time_field=_time"
    )

    if dry_run:
        print(f"\n[DRY RUN] Would POST {len(records)} records to:")
        print(f"  {url}")
        print(f"\nSample record:")
        print(json.dumps(records[0], indent=2))
        return True

    req = urllib.request.Request(
        url,
        data=ndjson.encode("utf-8"),
        method="POST",
        headers={"Content-Type": "application/stream+json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.getcode() == 200
    except urllib.error.HTTPError as e:
        print(f"  ERROR: HTTP {e.code} - {e.reason}")
        return False
    except urllib.error.URLError as e:
        print(f"  ERROR: Could not reach VictoriaLogs — {e.reason}")
        return False


# =============================================================================
# MAIN
# =============================================================================

def main():
    parser = argparse.ArgumentParser(description="Send inventory data to VictoriaLogs, one type per run")
    parser.add_argument("--dry-run", action="store_true", help="Preview without sending")
    parser.add_argument("--status",  action="store_true", help="Show what has/hasn't been sent")
    args = parser.parse_args()

    sent = load_sent()

    if args.status:
        print_status(sent)
        return

    print_status(sent)

    # find next pending type
    next_type = next((t for t in TYPES_ORDER if t not in sent), None)

    if not next_type:
        print("All component types have been sent. Nothing left to do.")
        return

    # load inventory
    script_dir = os.path.dirname(os.path.abspath(__file__))
    inventory_path = os.path.join(script_dir, INVENTORY_FILE)
    if not os.path.exists(inventory_path):
        print(f"ERROR: Inventory file not found: {INVENTORY_FILE}")
        sys.exit(1)

    with open(inventory_path) as f:
        data = json.load(f)

    # filter to next type only
    records = [build_record(item) for item in data if item["type"] == next_type]

    if not records:
        print(f"ERROR: No '{next_type}' components found in inventory file.")
        sys.exit(1)

    print(f"Sending : {next_type} ({len(records)} records)")
    print(f"Mode    : {'DRY RUN' if args.dry_run else 'LIVE'}\n")

    success = send(records, dry_run=args.dry_run)

    if success and not args.dry_run:
        mark_sent(next_type)
        print(f"  Done — {len(records)} {next_type} records sent to VictoriaLogs")

        # show what's a
        sent = load_sent()
        next_pending = next((t for t in TYPES_ORDER if t not in sent), None)
        if next_pending:
            print(f"  Next run will send: {next_pending}")
        else:
            print(f"  All types sent!")

        print(f"\nQuery in VictoriaLogs:")
        print(f'  All inventory  : {{log_source="inventory"}}')
        print(f'  Just {next_type:<10}: {{log_source="inventory"}} type:{next_type}')
        print(f'  By time        : {{log_source="inventory"}} _time:{datetime.now(timezone.utc).strftime("%Y-%m-%d")}')

    elif args.dry_run:
        print(f"\n  Dry run complete — nothing sent")
    else:
        print(f"\n  FAILED — nothing saved, will retry next run")


if __name__ == "__main__":
    main()
