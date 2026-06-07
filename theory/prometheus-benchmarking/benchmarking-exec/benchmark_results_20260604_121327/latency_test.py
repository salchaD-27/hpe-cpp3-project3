import requests
import time
import statistics
import json
import sys

VLSELECT_URL = "http://localhost:8004"
QUERY = "* | count()"
ITERATIONS = 50

print(f"\n  Running {ITERATIONS} iterations...")
times = []
for i in range(ITERATIONS):
    start = time.time()
    requests.get(f"{VLSELECT_URL}/select/logsql/query", params={"query": QUERY}, timeout=30)
    times.append((time.time() - start) * 1000)
    if (i + 1) % 10 == 0:
        print(f"    Progress: {i+1}/{ITERATIONS}")

times.sort()
print("\n" + "="*60)
print("  LATENCY PERCENTILES")
print("="*60)
print(f"\n  P50: {times[len(times)//2]:.2f} ms")
print(f"  P75: {times[int(len(times)*0.75)]:.2f} ms")
print(f"  P90: {times[int(len(times)*0.90)]:.2f} ms")
print(f"  P95: {times[int(len(times)*0.95)]:.2f} ms")
print(f"  P99: {times[int(len(times)*0.99)]:.2f} ms")
print(f"\n  Min: {times[0]:.2f} ms")
print(f"  Max: {times[-1]:.2f} ms")
print(f"  Avg: {statistics.mean(times):.2f} ms")

with open(sys.argv[1], 'w') as f:
    json.dump({"times": times, "p50": times[len(times)//2], "p95": times[int(len(times)*0.95)]}, f, indent=2)
