# #!/usr/bin/env python3
# """
# VictoriaLogs storage benchmark.
# Generates 3,006,295 synthetic syslog records from your original syslog.json
# and inserts them in batches directly into the local vlstorage.
# Run AFTER: docker compose up -d
# """

# import json
# import random
# import time
# import urllib.request
# import urllib.error
# import os
# import sys
# import copy
# from datetime import datetime, timedelta, timezone

# # ── config ────────────────────────────────────────────────────────────────────
# VL_URL        = "http://localhost:9999/insert/jsonline"
# TARGET_LOGS   = 3_006_295
# BATCH_SIZE    = 10_000
# BASE_DATE     = datetime(2026, 6, 6, 0, 0, 0, tzinfo=timezone.utc)

# # ── load original syslog.json ──────────────────────────────────────────────────
# def load_original_logs():
#     syslog_file = 'logs/syslog.json'

#     with open(syslog_file, 'r') as f:
#         data = json.load(f)

#     # OpenSearch _search response — extract _source from each hit
#     if 'hits' in data and 'hits' in data['hits']:
#         sources = [hit['_source'] for hit in data['hits']['hits']]
#         print(f"✅ Loaded {len(sources)} entries from OpenSearch response")
#         return sources

#     # Plain JSON array
#     if isinstance(data, list):
#         print(f"✅ Loaded {len(data)} entries from JSON array")
#         return data

#     print("❌ Unrecognised format")
#     return []

# def make_record_from_template(template: dict, index: int) -> dict:
#     ts = BASE_DATE + timedelta(
#         seconds=index % 86400,
#         microseconds=random.randint(0, 999999)
#     )

#     resource = template.get('Resource', {})
#     attrs    = template.get('Attributes', {})

#     return {
#         "_time":            ts.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z",
#         "_msg":             template.get('Body', ''),
#         "service_name":     random.choice(["systemd","sudo","sshd","cron",
#                                            "kernel","NetworkManager","rsyslog"]),
#         "host_name":        random.choice(["leader1","leader2","leader3",
#                                            "padma","vajra","compute-01"]),
#         "process_id":       str(random.randint(1, 99999)),
#         "severity":         random.choice(["info","info","info","warn","error"]),
#         "facility":         random.choice(["0","1","3","4","9","10","16"]),
#         "priority":         random.choice(["6","7","14","30","86","102","134"]),
#         "log_type":         attrs.get('type', 'log_syslog'),
#     }

# def post_batch(batch: list[dict], batch_num: int) -> bool:
#     """Post a batch of records to VictoriaLogs"""
#     try:
#         # Build payload as JSONL
#         payload = "\n".join(json.dumps(r) for r in batch)
        
#         # Encode to bytes
#         data = payload.encode('utf-8')
        
#         # Create request with proper headers
#         req = urllib.request.Request(
#             VL_URL,
#             data=data,
#             headers={
#                 "Content-Type": "application/json",
#                 "Content-Length": str(len(data))
#             },
#             method="POST"
#         )
        
#         # Send request with timeout
#         with urllib.request.urlopen(req, timeout=60) as resp:
#             status = resp.status
#             if status == 200:
#                 return True
#             else:
#                 print(f"  Batch {batch_num}: HTTP {status}")
#                 return False
                
#     except urllib.error.URLError as e:
#         print(f"  Batch {batch_num}: URL Error - {e}")
#         return False
#     except Exception as e:
#         print(f"  Batch {batch_num}: Error - {e}")
#         return False

# def wait_for_vl():
#     """Wait for VictoriaLogs to be ready"""
#     health = "http://localhost:9999/health"
#     print("Waiting for VictoriaLogs to be ready...", end="", flush=True)
#     for _ in range(30):
#         try:
#             with urllib.request.urlopen(health, timeout=2):
#                 print(" ready.")
#                 return
#         except Exception:
#             print(".", end="", flush=True)
#             time.sleep(2)
#     raise RuntimeError("VictoriaLogs not reachable at localhost:9999 after 60s")

# def main():
#     # Load original logs
#     print("📂 Loading original syslog.json...")
#     templates = load_original_logs()
    
#     if not templates:
#         print("❌ No log entries found in logs/syslog.json")
#         print("   Please check that logs/syslog.json exists and contains valid JSON")
#         return
    
#     print(f"   Using {len(templates)} templates to generate {TARGET_LOGS:,} logs")
    
#     wait_for_vl()
    
#     # Estimate file size
#     sample = make_record_from_template(templates[0], 0)
#     sample_size = len(json.dumps(sample).encode())
#     estimated_size_mb = (sample_size * TARGET_LOGS) / (1024 * 1024)
#     print(f"\n📊 Estimated raw size: {estimated_size_mb:.2f} MB")
#     print(f"   Batch size: {BATCH_SIZE} records/batch")
#     print(f"   Total batches: {(TARGET_LOGS + BATCH_SIZE - 1) // BATCH_SIZE:,}")
    
#     print(f"\n📥 Inserting {TARGET_LOGS:,} records...")
#     start      = time.time()
#     inserted   = 0
#     batch_num  = 0
#     failed_batches = 0
#     total_batches = (TARGET_LOGS + BATCH_SIZE - 1) // BATCH_SIZE

#     while inserted < TARGET_LOGS:
#         remaining  = TARGET_LOGS - inserted
#         this_batch = min(BATCH_SIZE, remaining)
        
#         # Generate batch
#         batch = []
#         for j in range(this_batch):
#             idx = inserted + j
#             template = templates[idx % len(templates)]
#             batch.append(make_record_from_template(template, idx))
        
#         # Post batch
#         ok = post_batch(batch, batch_num)
        
#         if ok:
#             inserted += this_batch
#             batch_num += 1
#             failed_batches = 0
#         else:
#             failed_batches += 1
#             print(f"  ⚠️  Batch {batch_num} failed (attempt {failed_batches})...")
#             if failed_batches > 5:
#                 print("❌ Too many consecutive failures. Exiting.")
#                 break
#             time.sleep(3)
#             continue

#         # Progress update every 50 batches
#         if batch_num % 50 == 0:
#             elapsed = time.time() - start
#             rate = inserted / elapsed if elapsed > 0 else 0
#             eta = (TARGET_LOGS - inserted) / rate if rate > 0 else 0
#             pct = inserted / TARGET_LOGS * 100
#             print(f"  [{pct:5.1f}%] {inserted:>10,} / {TARGET_LOGS:,} "
#                   f"| {rate:,.0f} logs/s | ETA {eta/60:.1f}m")

#     elapsed = time.time() - start
    
#     if inserted >= TARGET_LOGS:
#         print(f"\n✅ Done! {inserted:,} records in {elapsed/60:.1f}m "
#               f"({inserted/elapsed:,.0f} logs/s avg)")
#     else:
#         print(f"\n⚠️  Partial insertion: {inserted:,} records in {elapsed/60:.1f}m")
    
#     print("\n⏳ Waiting 60s for VictoriaLogs to flush and merge partitions...")
#     time.sleep(60)
    
#     # Verify count
#     print("\n🔍 Verifying inserted count...")
#     try:
#         req = urllib.request.Request("http://localhost:9999/select/logsql/stats_query")
#         req.add_header("Content-Type", "application/x-www-form-urlencoded")
        
#         data = "query=*%20%7C%20stats%20count()%20as%20total".encode()
#         with urllib.request.urlopen(req, data=data, timeout=10) as resp:
#             response = resp.read().decode()
#             print(f"   Response: {response[:200]}...")
            
#             # Extract count from response
#             import re
#             match = re.search(r'"value":\[\d+\.?\d*,"(\d+)"\]', response)
#             if match:
#                 count = int(match.group(1))
#                 print(f"   ✅ VictoriaLogs reports {count:,} logs")
#                 if count < inserted:
#                     print(f"   ⚠️  Mismatch: inserted {inserted:,}, found {count:,}")
#             else:
#                 print(f"   Could not extract count from response")
#     except Exception as e:
#         print(f"   Could not verify: {e}")

# if __name__ == "__main__":
#     main()



#!/usr/bin/env python3
"""
Generate 3,006,295 COMPLETELY UNIQUE logs
No repetition of messages, random strings, unique timestamps
"""

import json
import random
import time
import urllib.request
from datetime import datetime, timedelta, timezone
import string

VL_URL = "http://localhost:9999/insert/jsonline"
TARGET_LOGS = 3_006_295
BATCH_SIZE = 10000
BASE_DATE = datetime(2026, 6, 6, 0, 0, 0, tzinfo=timezone.utc)

# Generate unique messages on-the-fly
def random_string(length=10):
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))

def generate_unique_log(index: int) -> dict:
    """Generate a completely unique log - no repeated values except field names"""
    ts = BASE_DATE + timedelta(seconds=index % 86400, microseconds=index * 37 % 1000000)
    
    return {
        "_time": ts.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z",
        "_msg": f"Unique message #{index} with random {random_string(20)} and content {random_string(50)}",
        "service": random_string(12),  # Completely unique service name
        "host": f"host-{random_string(8)}-{index % 10000:04d}",
        "severity": random.choice(["INFO", "WARN", "ERROR", "DEBUG", "CRITICAL"]),  # Only 5 repeated
        "trace_id": f"{random_string(32)}",  # Unique
        "user_id": f"user-{random.randint(1, 1000000)}",  # Semi-unique
        "session_id": f"sess-{random_string(16)}",  # Unique
    }

def post_batch(batch):
    payload = "\n".join(json.dumps(r) for r in batch).encode()
    req = urllib.request.Request(VL_URL, data=payload, headers={"Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status == 200
    except:
        return False

def main():
    print(f"Generating {TARGET_LOGS:,} COMPLETELY UNIQUE logs...")
    print("Every log has unique: message, service name, host, trace_id, session_id")
    print("Only severity has 5 unique values.")
    print()
    
    start = time.time()
    inserted = 0
    
    while inserted < TARGET_LOGS:
        remaining = TARGET_LOGS - inserted
        this_batch = min(BATCH_SIZE, remaining)
        batch = [generate_unique_log(inserted + j) for j in range(this_batch)]
        
        if post_batch(batch):
            inserted += this_batch
        else:
            print(f"Retrying batch...")
            time.sleep(2)
            continue
        
        if inserted % 100000 == 0:
            elapsed = time.time() - start
            rate = inserted / elapsed
            print(f"  {inserted:,} / {TARGET_LOGS:,} ({rate:.0f} logs/s)")

    elapsed = time.time() - start
    print(f"\n✅ Done! {inserted:,} logs in {elapsed/60:.1f}m")
    print("⏳ Waiting for merges...")
    time.sleep(60)

if __name__ == "__main__":
    main()