from statistics import mean, stdev
import subprocess
from tracemalloc import start
from urllib.parse import quote

import requests
import time
from concurrent.futures import ThreadPoolExecutor
from collections import defaultdict

# Configuration
TIMEOUT = 30
timeouts = 0
success = 0
failure = 0
VUS = 5                  # Virtual users
DURATION = 60            # 1 minutes in seconds
URL = "http://localhost:9428/select/logsql/query?query={query}"
latencies_by_query = defaultdict(list)
response_bytes = []
queries = [
    "log_source:syslog OR _msg:'Started' | stats count() as restarts | filter restarts:>1",
    "* | extract '<ip> *' from _msg | replace('10.1.1.11', 'node-a') | replace('10.1.1.12', 'node-b') | replace('10.1.1.13', 'node-c') | replace('10.1.1.14', 'node-d') | replace('10.1.1.15', 'node-e') | format '<_msg>' as formatted | stats by (formatted) count() as hits | filter hits :> 0",
    "* | copy 'Resource.service.name' as service | copy 'Resource.host.name' as host | copy 'Attributes.priority' as priority_raw | math priority_raw + 0 as priority | format '<host> : <service> : <_msg>' as formatted | stats by (formatted) count() if (host:='padma' OR service:in('systemd', 'glusterd') OR priority:range[70, Inf]) as CRITICAL, count() if (priority:range[30, 70) AND host:!='padma' AND service:!in('systemd', 'glusterd')) as WARN, count() if (priority:range[0, 30) AND host:!='padma' AND service:!in('systemd', 'glusterd')) as SAFE",
    "* | copy 'Resource.service.name' as service | copy 'Resource.host.name' as host | copy _msg as message | format '<host> | <service> | <message>' as formatted | stats by (formatted) count() as cnt | filter cnt:>0",
    "*| copy 'Resource.service.name' as service | copy 'Resource.host.name' as host | copy 'Attributes.priority' as priority_raw | copy _msg as message | replace('10.1.1.11', 'node-a') | replace('10.1.1.12', 'node-b') | replace('10.1.1.13', 'node-c') | replace('10.1.1.14', 'node-d') | replace('10.1.1.15', 'node-e') | math priority_raw + 0 as priority | format '<host> | <service> | <message>' as formatted | stats by (formatted) count() if (host:='padma' OR service:in('systemd','glusterd') OR priority:range[70, Inf]) as CRITICAL, count() if (priority:range[30,70) AND host:!='padma' AND service:!in('systemd','glusterd')) as WARN, count() if (priority:range[0,30) AND host:!='padma' AND service:!in('systemd','glusterd')) as SAFE | filter CRITICAL:>0 OR WARN:>0"
]


def worker(end_time, query):
    while time.time() < end_time:
        try:
            # for query in queries:
            start = time.perf_counter()
            # print(quote(queries[2]))
            response = requests.get(
                "http://localhost:9428/select/logsql/query",
                params={"query": query},
                timeout=TIMEOUT
            )
            response_bytes.append(len(response.content))
            latency = time.perf_counter() - start

            latencies_by_query[query].append(latency)
            # print(response.status_code, latency)
            # print(
            #     f"status={response.status_code} "
            #     f"latency={latency:.3f}s"
            # )
            # print(response.request.url)

            if response.status_code == 200:
                global success
                success += 1
            else:
                global failure
                failure += 1
            # print(f"Worker finished with {len(latencies_by_query[query])} requests for query: {query}")
        except requests.Timeout:
            global timeouts
            timeouts += 1
            # print(f"Timeout for query: {query}")
        except Exception as e:
            print(f"Error: {e}")

def percentile(data, p):
    data = sorted(data)
    idx = int(len(data) * p / 100)
    idx = min(idx, len(data) - 1)
    return data[idx]

def main():
    end_time = time.time() + DURATION

    with ThreadPoolExecutor(max_workers=VUS) as executor:
        for _ in range(VUS):
            for query in queries:
                executor.submit(worker, end_time, query)

    for query in queries:
        latencies = latencies_by_query[query]
        print("-"*50)
        print(f"Executed query: {query}")
        print("-"*50)
        print("\n=== 1. Latency Results ===")
        print(f"Requests: {len(latencies)}")
        print(f"p50: {percentile(latencies, 50):.3f}s")
        print(f"p95: {percentile(latencies, 95):.3f}s")
        print(f"p99: {percentile(latencies, 99):.3f}s")
        print(f"max: {max(latencies):.3f}s")
        print(f"min latency: {min(latencies):.3f}s")
        print(f"avg latency: {mean(latencies):.3f}s")
        print(f"latency stddev: {stdev(latencies):.3f}s")
        print("-"*50)
        print("\n=== 2. Throughput (QPS) Results ===")
        print(f"Total duration: {DURATION} seconds")
        print(f"Throughput: {len(latencies) / DURATION:.2f} QPS")
        print("-"*50)
        print("\n=== 3. Success/Failure Rate ===")
        print(f"success: {success}")
        print(f"failure: {failure}")
        print(f"success rate: {success / (success + failure) * 100:.2f}%")
        print(f"failure rate: {failure / (success + failure) * 100:.2f}%")
        print("-"*50)
        print("\n=== 4. Response Size Results ===")
        print(f"avg response size = {mean(response_bytes)/1024:.2f} KB")
        print(f"max response size = {max(response_bytes)/1024:.2f} KB")
        print("-"*50)
        print("\n=== 5. Requests per Worker ===")
        requests_per_worker = len(latencies) / VUS
        print(f"requests per worker: {requests_per_worker:.2f}")
        print("-"*50)
        print("\n=== 6. Timeout Count ===")
        print(f"timeouts: {timeouts}")
        print("-"*50)
        print("\n=== 7. Slow Query Count ===")
        slow_1s = sum(1 for x in latencies if x > 1)
        slow_2s = sum(1 for x in latencies if x > 2)
        slow_5s = sum(1 for x in latencies if x > 5)
        print(f">1s queries: {slow_1s}")
        print(f">2s queries: {slow_2s}")
        print(f">5s queries: {slow_5s}")
        print("-"*50)
        print("\n=== 8. Total Data Downloaded ===")
        total_bytes = sum(response_bytes)
        print(f"total downloaded: {total_bytes/1024/1024:.2f} MB")
        print("-"*50)
        print("\n=== 9. Data Throughput ===")
        mbps = (sum(response_bytes) / 1024 / 1024) / DURATION
        print(f"data throughput: {mbps:.2f} MB/s")
        print("-"*50)
        print("\n=== 10. Warm vs Cold Latency ===")
        cold_latency = latencies[0]
        warm_latency = mean(latencies[1:])
        print(f"cold latency: {cold_latency:.3f}s")
        print(f"warm latency: {warm_latency:.3f}s")
        print("-"*50)
        print("\n=== 11. Server Memory Usage ===")
        mem = subprocess.check_output([
                "docker",
                "stats",
                "--no-stream",
                "--format",
                "{{.MemUsage}}",
                "victorialogs"
            ]).decode().strip()
        print(f"Memory Usage: {mem}")
        print("-"*50)
        print("\n=== 12. Server CPU Usage ===")
        cpu = subprocess.check_output([
                "docker",
                "stats",
                "--no-stream",
                "--format",
                "{{.CPUPerc}}",
                "victorialogs"
            ]).decode().strip()
        print(f"CPU Usage: {cpu}")
        print("-"*50)
        print("\n=== 13. Concurrency Efficiency ===")
        print("-"*50)


if __name__ == "__main__":
    main()