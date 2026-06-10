from tracemalloc import start
from urllib.parse import quote

import requests
import time
from concurrent.futures import ThreadPoolExecutor
from collections import defaultdict

# Configuration
VUS = 5                  # Virtual users
DURATION = 60            # 1 minutes in seconds
URL = "http://localhost:9428/select/logsql/query?query={query}"
latencies_by_query = defaultdict(list)
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
                params={"query": query}
            )
            latency = time.perf_counter() - start

            latencies_by_query[query].append(latency)
            # print(response.status_code, latency)
            # print(
            #     f"status={response.status_code} "
            #     f"latency={latency:.3f}s"
            # )
            # print(response.request.url)

            if response.status_code != 200:
                print(f"Error: {response.text}")
            # print(f"Worker finished with {len(latencies_by_query[query])} requests for query: {query}")
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
        print(f"Executed query: {query}")
        print("\n=== Results ===")
        print(f"Requests: {len(latencies)}")
        print(f"p50: {percentile(latencies, 50):.3f}s")
        print(f"p95: {percentile(latencies, 95):.3f}s")
        print(f"p99: {percentile(latencies, 99):.3f}s")
        print(f"max: {max(latencies):.3f}s")


if __name__ == "__main__":
    main()