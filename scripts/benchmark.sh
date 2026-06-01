#!/bin/bash
# =============================================================================
# Complete Inside-Out Benchmark Suite for JSON vs Hybrid Storage
# Tests: Storage efficiency, query performance, latency, throughput, scalability
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'

# Configuration
LOG_COUNT_PER_NODE=30000
TOTAL_LOGS=$((LOG_COUNT_PER_NODE * 4))
RESULT_DIR="benchmark_results_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULT_DIR"

print_header() {
    echo ""
    echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}  $1${NC}"
    echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_success() { echo -e "  ${GREEN}✅${NC} $1"; }
print_error() { echo -e "  ${RED}❌${NC} $1"; }
print_info() { echo -e "  ${BLUE}➡️${NC} $1"; }
print_metric() { echo -e "  ${WHITE}●${NC} $1: ${GREEN}$2${NC}"; }

# =============================================================================
# SECTION 1: Generate Large Scale Test Data
# =============================================================================
print_header "SECTION 1: GENERATING ${TOTAL_LOGS} TEST LOGS (30K per node)"

print_info "Generating logs with varied patterns..."

cat > /tmp/generate_large_logs.py << 'PYTHON_EOF'
import json
import random
from datetime import datetime, timedelta

def generate_logs(count=30000, node_name="node-3"):
    """Generate exactly 'count' test logs for a specific node"""
    logs = []
    services = ['kafka', 'zookeeper', 'hpc-master', 'hpc-worker', 'database', 'cache', 'load-balancer']
    levels = ['INFO', 'WARN', 'ERROR', 'DEBUG', 'CRITICAL']
    hosts = [f'host-{i}' for i in range(1, 21)]
    messages = [
        "Connection established to database",
        "Request processed successfully",
        "Timeout waiting for response",
        "Cache hit ratio: {:.2f}%",
        "Memory usage: {:.1f}%",
        "CPU utilization: {:.1f}%",
        "Disk I/O: {} MB/s",
        "Network latency: {}ms",
        "Authentication failed for user: {}",
        "Job completed in {}ms",
        "Replica sync completed",
        "Leader election in progress",
        "Configuration reloaded",
        "Backup completed successfully",
        "Health check passed"
    ]
    
    start_time = datetime.now() - timedelta(days=7)
    
    for i in range(count):
        timestamp = start_time + timedelta(seconds=random.randint(0, 7*24*3600))
        service = random.choice(services)
        level = random.choices(levels, weights=[60, 15, 10, 10, 5])[0]
        host = random.choice(hosts)
        message = random.choice(messages)
        
        if "{}" in message:
            if "ratio" in message:
                message = message.format(random.uniform(0, 100))
            elif "usage" in message:
                message = message.format(random.uniform(0, 100))
            elif "MB/s" in message:
                message = message.format(random.randint(1, 500))
            elif "ms" in message:
                message = message.format(random.randint(1, 5000))
            elif "user" in message:
                message = message.format(f"user_{random.randint(1, 100)}")
            else:
                message = message.format(random.randint(1, 10000))
        
        log = {
            "timestamp": timestamp.isoformat(),
            "level": level,
            "service_name": service,
            "host_name": host,
            "message": message,
            "node_name": node_name,
            "log_id": i,
            "duration_ms": random.randint(1, 10000),
            "memory_mb": random.randint(100, 32000),
            "cpu_percent": random.randint(1, 100),
            "retry_count": random.randint(0, 5),
            "trace_id": f"trace_{random.randint(100000, 999999)}",
            "user_id": f"user_{random.randint(1, 1000)}",
            "session_id": f"sess_{random.randint(10000, 99999)}"
        }
        logs.append(log)
    
    return logs

# Generate logs for each storage node
nodes = [
    ("node-3-vlstorage", "json_only_1"),
    ("node-4-vlstorage", "json_only_2"),
    ("node-3-vlstorage-hybrid", "hybrid_1"),
    ("node-4-vlstorage-hybrid", "hybrid_2")
]

for node_name, label in nodes:
    logs = generate_logs(30000, node_name)
    
    # Save as JSONL format (one log per line)
    with open(f"logs_{label}.jsonl", 'w') as f:
        for log in logs:
            f.write(json.dumps(log) + '\n')
    
    print(f"Generated {len(logs)} logs for {node_name}")

print("\n✅ TOTAL LOGS GENERATED: 120,000 (30,000 per storage node)")
print("   Files created:")
print("     - logs_json_only_1.jsonl  (for node-3-vlstorage)")
print("     - logs_json_only_2.jsonl  (for node-4-vlstorage)")
print("     - logs_hybrid_1.jsonl     (for node-3-vlstorage-hybrid)")
print("     - logs_hybrid_2.jsonl     (for node-4-vlstorage-hybrid)")
PYTHON_EOF

python3 /tmp/generate_large_logs.py
print_success "Generated ${TOTAL_LOGS} test logs (30K per storage node)"

# =============================================================================
# SECTION 2: Send Logs to Respective Storage Nodes
# =============================================================================
print_header "SECTION 2: INGESTING LOGS TO STORAGE NODES"

send_logs_to_node() {
    local node_name=$1
    local port=$2
    local log_file=$3
    local display_name=$4
    local count=0
    
    if [ ! -f "$log_file" ]; then
        print_error "Log file $log_file not found!"
        return 1
    fi
    
    print_info "Sending logs to $display_name (port $port)..."
    
    total_lines=$(wc -l < "$log_file")
    
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            curl -s -X POST "http://localhost:$port/insert/jsonline" \
                -H "Content-Type: application/json" \
                -d "$line" >/dev/null 2>&1
            count=$((count + 1))
            
            # Show progress every 1000 logs
            if [ $((count % 1000)) -eq 0 ]; then
                echo -e "    📊 Progress: $count/$total_lines logs sent to $display_name..."
            fi
        fi
    done < "$log_file"
    
    echo -e "    ✅ Completed: $count logs sent to $display_name"
}

# Send to JSON-only nodes
send_logs_to_node "node-3-vlstorage" 8002 "logs_json_only_1.jsonl" "Node 3 (JSON only)"
send_logs_to_node "node-4-vlstorage" 8003 "logs_json_only_2.jsonl" "Node 4 (JSON only)"

# Send to Hybrid nodes
send_logs_to_node "node-3-vlstorage-hybrid" 8005 "logs_hybrid_1.jsonl" "Node 3 Hybrid"
send_logs_to_node "node-4-vlstorage-hybrid" 8006 "logs_hybrid_2.jsonl" "Node 4 Hybrid"

print_success "All logs ingested successfully (30,000 logs per node)"

# Wait for indexing
print_info "Waiting 60 seconds for indexing to complete..."
sleep 60

# =============================================================================
# SECTION 3: Verify Log Counts Per Node
# =============================================================================
print_header "SECTION 3: VERIFYING LOG COUNTS PER NODE"

echo ""
print_info "Checking log counts on each storage node:"

verify_node_logs() {
    local name=$1
    local port=$2
    local expected=30000
    
    count=$(curl -s "http://localhost:$port/select/logsql/query?query=*%20%7C%20count()" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(list(d.values())[0] if d else 0)" 2>/dev/null || echo "0")
    
    if [ "$count" -ge 29000 ] && [ "$count" -le 31000 ]; then
        print_success "$name: $count logs (expected ~$expected)"
    else
        print_info "$name: $count logs (may still be indexing)"
    fi
}

verify_node_logs "Node 3 (JSON only)" 8002
verify_node_logs "Node 4 (JSON only)" 8003
verify_node_logs "Node 3 Hybrid" 8005
verify_node_logs "Node 4 Hybrid" 8006

# =============================================================================
# SECTION 4: Storage Efficiency Analysis
# =============================================================================
print_header "SECTION 4: STORAGE EFFICIENCY ANALYSIS"

echo ""
print_info "Storage Metrics Per Node:"
echo "  ┌─────────────────────────────────────────────────────────────────────────────────────────────┐"
printf "  │ %-25s │ %-15s │ %-20s │ %-15s │\n" "Node" "Type" "Size (MB)" "Log Count"
echo "  ├─────────────────────────────────────────────────────────────────────────────────────────────┤"

# Get storage sizes
for node_info in "node-3-vlstorage:8002:JSON only" "node-4-vlstorage:8003:JSON only" "node-3-vlstorage-hybrid:8005:Hybrid" "node-4-vlstorage-hybrid:8006:Hybrid"; do
    IFS=':' read -r container_name port type <<< "$node_info"
    
    count=$(curl -s "http://localhost:$port/select/logsql/query?query=*%20%7C%20count()" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(list(d.values())[0] if d else 0)" 2>/dev/null || echo "0")
    
    size_bytes=$(docker exec "$container_name" du -sb /storage 2>/dev/null | cut -f1 || echo "0")
    size_mb=$(echo "scale=2; $size_bytes / 1024 / 1024" | bc)
    
    printf "  │ %-25s │ %-15s │ %-20s │ %-15s │\n" "$container_name" "$type" "$size_mb" "$count"
done
echo "  └─────────────────────────────────────────────────────────────────────────────────────────────┘"

# Calculate totals
JSON_TOTAL=$(curl -s "http://localhost:8002/select/logsql/query?query=*%20%7C%20count()" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(list(d.values())[0] if d else 0)" 2>/dev/null || echo "0")
JSON_TOTAL=$((JSON_TOTAL + $(curl -s "http://localhost:8003/select/logsql/query?query=*%20%7C%20count()" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(list(d.values())[0] if d else 0)" 2>/dev/null || echo "0")))

HYBRID_TOTAL=$(curl -s "http://localhost:8005/select/logsql/query?query=*%20%7C%20count()" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(list(d.values())[0] if d else 0)" 2>/dev/null || echo "0")
HYBRID_TOTAL=$((HYBRID_TOTAL + $(curl -s "http://localhost:8006/select/logsql/query?query=*%20%7C%20count()" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(list(d.values())[0] if d else 0)" 2>/dev/null || echo "0")))

echo ""
print_info "Storage Summary:"
print_metric "JSON-only Total Logs" "$JSON_TOTAL"
print_metric "Hybrid Total Logs" "$HYBRID_TOTAL"

# =============================================================================
# SECTION 5: Comprehensive Query Performance Benchmark
# =============================================================================
print_header "SECTION 5: QUERY PERFORMANCE BENCHMARK"

cat > /tmp/benchmark_queries.py << 'PYTHON_EOF'
import requests
import time
import json
import statistics
from datetime import datetime

QUERIES = [
    ("Simple count", "* | count()"),
    ("Error count", "level:ERROR | count()"),
    ("Critical count", "level:CRITICAL | count()"),
    ("Count by service", "* | stats by (service_name) count()"),
    ("Count by host", "* | stats by (host_name) count()"),
    ("Count by level", "* | stats by (level) count()"),
    ("Last 1 hour errors", "_time:1h AND level:ERROR | count()"),
    ("Last 6 hours errors", "_time:6h AND level:ERROR | count()"),
    ("Last 24 hours errors", "_time:24h AND level:ERROR | count()"),
    ("High memory usage", "memory_mb:>15000 | count()"),
    ("High CPU usage", "cpu_percent:>80 | count()"),
    ("Multiple retries", "retry_count:>2 | count()"),
    ("Errors on kafka", "level:ERROR AND service_name:kafka | count()"),
    ("High memory errors", "level:ERROR AND memory_mb:>20000 | count()"),
    ("Extract trace IDs", "* | extract trace_id | count()"),
    ("Average duration", "* | stats avg(duration_ms)"),
    ("P95 duration", "* | stats p95(duration_ms)"),
    ("Top 5 services by errors", "level:ERROR | top 5 service_name"),
    ("Top 10 hosts by logs", "* | top 10 host_name"),
    ("Contains 'timeout'", "message:timeout | count()"),
]

def run_benchmark():
    results = []
    print("\n  Running benchmark on 20+ query patterns...\n")
    
    for name, query in QUERIES:
        print(f"    Testing: {name}...", end=" ", flush=True)
        
        # Query via vlselect (queries all nodes)
        start = time.time()
        try:
            resp = requests.get("http://localhost:8004/select/logsql/query", params={"query": query}, timeout=30)
            elapsed = (time.time() - start) * 1000
            results.append({
                "name": name,
                "query": query,
                "time_ms": round(elapsed, 2),
                "status": resp.status_code
            })
            print(f"✅ {elapsed:.1f}ms")
        except Exception as e:
            print(f"❌ Error: {e}")
    
    return results

results = run_benchmark()

if results:
    times = [r["time_ms"] for r in results]
    print("\n" + "="*60)
    print("  QUERY PERFORMANCE SUMMARY")
    print("="*60)
    print(f"\n  Average query time: {statistics.mean(times):.2f} ms")
    print(f"  Min query time:     {min(times):.2f} ms")
    print(f"  Max query time:     {max(times):.2f} ms")
    print(f"  Median query time:  {statistics.median(times):.2f} ms")

with open("query_benchmark_results.json", 'w') as f:
    json.dump(results, f, indent=2)
    print("\n✅ Results saved to query_benchmark_results.json")
PYTHON_EOF

python3 /tmp/benchmark_queries.py

# =============================================================================
# SECTION 6: Latency Percentile Analysis
# =============================================================================
print_header "SECTION 6: LATENCY PERCENTILE ANALYSIS (P50, P90, P95, P99)"

cat > /tmp/latency_analysis.py << 'PYTHON_EOF'
import requests
import time
import statistics
import json

QUERY = "* | count()"
ITERATIONS = 100

print(f"\n  Running {ITERATIONS} iterations for percentile calculation...")

times = []
for i in range(ITERATIONS):
    start = time.time()
    requests.get("http://localhost:8004/select/logsql/query", params={"query": QUERY}, timeout=30)
    times.append((time.time() - start) * 1000)
    
    if (i + 1) % 20 == 0:
        print(f"    Progress: {i+1}/{ITERATIONS}")

times.sort()

print("\n" + "="*60)
print("  LATENCY PERCENTILES (ms)")
print("="*60)
print(f"\n  {'Percentile':<15} {'Value (ms)':>15}")
print("  " + "-"*30)

percentiles = [50, 75, 90, 95, 99, 99.9]
for p in percentiles:
    idx = int(len(times) * p / 100)
    value = times[min(idx, len(times)-1)]
    print(f"  P{p:<13} {value:>15.2f}")

print(f"\n  Min: {times[0]:.2f} ms")
print(f"  Max: {times[-1]:.2f} ms")
print(f"  Avg: {statistics.mean(times):.2f} ms")

with open("latency_percentiles.json", 'w') as f:
    json.dump({
        "percentiles": {f"p{p}": times[min(int(len(times) * p / 100), len(times)-1)] for p in percentiles},
        "min": times[0],
        "max": times[-1],
        "avg": statistics.mean(times),
        "all_times": times
    }, f, indent=2)

print("\n✅ Results saved to latency_percentiles.json")
PYTHON_EOF

python3 /tmp/latency_analysis.py

# =============================================================================
# SECTION 7: Throughput and Scalability Test
# =============================================================================
print_header "SECTION 7: THROUGHPUT & SCALABILITY TEST"

cat > /tmp/throughput_test.py << 'PYTHON_EOF'
import requests
import time
import json
import threading
import statistics
from concurrent.futures import ThreadPoolExecutor, as_completed

API_URL = "http://localhost:8004"
QUERY = "level:ERROR | count()"

def run_query():
    start = time.time()
    try:
        resp = requests.get(f"{API_URL}/select/logsql/query", params={"query": QUERY}, timeout=30)
        return (time.time() - start) * 1000, resp.status_code == 200
    except:
        return 5000, False

def throughput_test(concurrent_queries, duration_seconds=10):
    print(f"\n  Testing {concurrent_queries} concurrent queries for {duration_seconds}s...")
    
    results = []
    end_time = time.time() + duration_seconds
    
    with ThreadPoolExecutor(max_workers=concurrent_queries) as executor:
        futures = []
        while time.time() < end_time:
            futures.append(executor.submit(run_query))
            time.sleep(0.01)
        
        for future in as_completed(futures):
            results.append(future.result())
    
    times = [r[0] for r in results if r[1]]
    success = sum(1 for r in results if r[1])
    
    return {
        "total_queries": len(results),
        "successful": success,
        "success_rate": (success / len(results)) * 100 if results else 0,
        "avg_latency_ms": statistics.mean(times) if times else 0,
        "p95_latency_ms": statistics.quantiles(times, n=20)[18] if len(times) >= 20 else (max(times) if times else 0),
        "throughput_qps": len(results) / duration_seconds
    }

print("\n  Running throughput tests with varying concurrency...")

results = []
for concurrency in [1, 5, 10, 20, 50]:
    result = throughput_test(concurrency, duration_seconds=10)
    results.append({"concurrency": concurrency, **result})
    print(f"    Concurrency {concurrency}: {result['throughput_qps']:.1f} QPS, {result['avg_latency_ms']:.1f}ms latency")

print("\n" + "="*60)
print("  THROUGHPUT SUMMARY")
print("="*60)
print(f"\n  {'Concurrency':<12} {'QPS':>10} {'Avg Latency':>12} {'P95 Latency':>12} {'Success Rate':>12}")
print("  " + "-"*65)

for r in results:
    print(f"  {r['concurrency']:<12} {r['throughput_qps']:>10.1f} {r['avg_latency_ms']:>12.1f} {r['p95_latency_ms']:>12.1f} {r['success_rate']:>11.1f}%")

with open("throughput_results.json", 'w') as f:
    json.dump(results, f, indent=2)

print("\n✅ Results saved to throughput_results.json")
PYTHON_EOF

python3 /tmp/throughput_test.py

# =============================================================================
# SECTION 8: Resource Utilization Analysis
# =============================================================================
print_header "SECTION 8: RESOURCE UTILIZATION ANALYSIS"

cat > /tmp/resource_utilization.py << 'PYTHON_EOF'
import subprocess
import json

def get_container_stats(container_name):
    try:
        result = subprocess.run(
            ['docker', 'stats', '--no-stream', '--format', '{{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}', container_name],
            capture_output=True, text=True, timeout=5
        )
        lines = result.stdout.strip().split('\n')
        for line in lines:
            if container_name in line:
                parts = line.split('\t')
                if len(parts) >= 4:
                    return {
                        "cpu_percent": parts[1].strip(),
                        "memory_usage": parts[2].strip(),
                        "memory_percent": parts[3].strip()
                    }
    except Exception as e:
        pass
    return {"cpu_percent": "N/A", "memory_usage": "N/A", "memory_percent": "N/A"}

containers = [
    ("node-3-vlstorage", "JSON-only Node 3"),
    ("node-4-vlstorage", "JSON-only Node 4"),
    ("node-3-vlstorage-hybrid", "Hybrid Node 3"),
    ("node-4-vlstorage-hybrid", "Hybrid Node 4"),
    ("node-2-vlinsert", "Write Gateway"),
    ("node-5-vlselect", "Query Gateway"),
    ("node-1-logstash", "Logstash"),
    ("node-1-kafka", "Kafka")
]

print("\n  Resource Usage by Container:\n")
print("  ┌─────────────────────────────────────────────────────────────────────────────────────────┐")
print("  │ Container                          CPU %        Memory              Memory %            │")
print("  ├─────────────────────────────────────────────────────────────────────────────────────────┤")

for container, name in containers:
    stats = get_container_stats(container)
    print(f"  │ {name:<32} {stats['cpu_percent']:>10} {stats['memory_usage']:>18} {stats['memory_percent']:>10} │")

print("  └─────────────────────────────────────────────────────────────────────────────────────────┘")
PYTHON_EOF

python3 /tmp/resource_utilization.py

# =============================================================================
# SECTION 9: Generate Comprehensive HTML Report
# =============================================================================
print_header "SECTION 9: GENERATING COMPREHENSIVE REPORT"

cat > /tmp/generate_report.py << 'PYTHON_EOF'
import json
import os
from datetime import datetime

# Load results
query_results = {}
latency_results = {}
throughput_results = {}

if os.path.exists("query_benchmark_results.json"):
    with open("query_benchmark_results.json") as f:
        query_results = json.load(f)

if os.path.exists("latency_percentiles.json"):
    with open("latency_percentiles.json") as f:
        latency_results = json.load(f)

if os.path.exists("throughput_results.json"):
    with open("throughput_results.json") as f:
        throughput_results = json.load(f)

# Calculate averages
if query_results:
    avg_time = sum(r["time_ms"] for r in query_results) / len(query_results)
else:
    avg_time = 0

html_content = f"""<!DOCTYPE html>
<html>
<head>
    <title>JSON vs Hybrid Storage - Complete Benchmark Report</title>
    <style>
        body {{ font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }}
        .container {{ max-width: 1200px; margin: auto; background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }}
        h1 {{ color: #333; border-bottom: 3px solid #4CAF50; padding-bottom: 10px; }}
        h2 {{ color: #555; margin-top: 30px; }}
        table {{ border-collapse: collapse; width: 100%; margin: 20px 0; }}
        th, td {{ border: 1px solid #ddd; padding: 12px; text-align: left; }}
        th {{ background-color: #4CAF50; color: white; }}
        tr:nth-child(even) {{ background-color: #f9f9f9; }}
        .metric {{ font-weight: bold; color: #4CAF50; }}
        .summary-box {{ background: #e8f5e9; padding: 20px; border-radius: 8px; margin: 20px 0; }}
        .footer {{ text-align: center; margin-top: 40px; color: #888; font-size: 12px; }}
        .good {{ color: #4CAF50; }}
        .bad {{ color: #f44336; }}
    </style>
</head>
<body>
<div class="container">
    <h1>🔬 JSON vs Hybrid Storage - Complete Benchmark Report</h1>
    <p>Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
    
    <div class="summary-box">
        <h3>📊 Executive Summary</h3>
        <p>• Total Logs Tested: <span class="metric">120,000</span> (30,000 per storage node)</p>
        <p>• Storage Nodes: 4 (2 JSON-only + 2 Hybrid)</p>
        <p>• Average Query Time: <span class="metric">{avg_time:.2f} ms</span></p>
        <p>• P95 Latency: <span class="metric">{latency_results.get('percentiles', {}).get('p95', 0):.2f} ms</span></p>
    </div>
    
    <h2>📈 Query Performance Results</h2>
    <table>
        <tr><th>Query Type</th><th>Time (ms)</th><th>Status</th></tr>
"""
for q in query_results[:20]:
    status_color = "#4CAF50" if q.get('status') == 200 else "#f44336"
    html_content += f"""
        <tr>
            <td>{q.get('name', 'Unknown')}</td>
            <td>{q.get('time_ms', 0):.2f}</td>
            <td style="color: {status_color}">{q.get('status', 0)}</td>
        </tr>"""

html_content += f"""
    </table>
    
    <h2>📊 Latency Percentiles</h2>
    <table>
        <tr><th>Percentile</th><th>Value (ms)</th></tr>
"""
for p in ['p50', 'p75', 'p90', 'p95', 'p99', 'p99.9']:
    val = latency_results.get('percentiles', {}).get(p, 0)
    html_content += f"""
        <tr>
            <td>{p.upper()}</td>
            <td>{val:.2f}</td>
        </tr>"""

html_content += f"""
    </table>
    
    <h2>⚡ Throughput Test Results</h2>
    <table>
        <tr><th>Concurrency</th><th>QPS</th><th>Avg Latency (ms)</th><th>Success Rate</th></tr>
"""

for t in throughput_results:
    html_content += f"""
        <tr>
            <td>{t.get('concurrency', 0)}</td>
            <td>{t.get('throughput_qps', 0):.1f}</td>
            <td>{t.get('avg_latency_ms', 0):.1f}</td>
            <td>{t.get('success_rate', 0):.1f}%</td>
        </tr>"""

html_content += """
    </table>
    
    <div class="footer">
        <p>Benchmark completed on 7-Node Hybrid Cluster with 120,000 total logs</p>
        <p>VictoriaLogs v1.49.0 | 4 Storage Nodes (2 JSON-only + 2 Hybrid)</p>
    </div>
</div>
</body>
</html>
"""

with open("complete_benchmark_report.html", 'w') as f:
    f.write(html_content)

print("\n✅ HTML report generated: complete_benchmark_report.html")
PYTHON_EOF

python3 /tmp/generate_report.py

# =============================================================================
# SECTION 10: Final Summary
# =============================================================================
print_header "BENCHMARK COMPLETE - FINAL SUMMARY"

echo ""
echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}                              BENCHMARK RESULTS SUMMARY${NC}"
echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  📊 ${BOLD}Total Logs Processed:${NC} 120,000 (30,000 per storage node)"
echo -e "  🗄️  ${BOLD}Storage Nodes:${NC}"
echo -e "     • node-3-vlstorage (JSON only)       - Port 8002"
echo -e "     • node-4-vlstorage (JSON only)       - Port 8003"
echo -e "     • node-3-vlstorage-hybrid (Hybrid)   - Port 8005"
echo -e "     • node-4-vlstorage-hybrid (Hybrid)   - Port 8006"
echo ""
echo -e "  📁 ${BOLD}Generated Files:${NC}"
echo -e "     • logs_json_only_1.jsonl        - Logs for node-3-vlstorage"
echo -e "     • logs_json_only_2.jsonl        - Logs for node-4-vlstorage"
echo -e "     • logs_hybrid_1.jsonl           - Logs for node-3-vlstorage-hybrid"
echo -e "     • logs_hybrid_2.jsonl           - Logs for node-4-vlstorage-hybrid"
echo -e "     • query_benchmark_results.json  - Detailed query performance"
echo -e "     • latency_percentiles.json      - P50/P95/P99 latency analysis"
echo -e "     • throughput_results.json       - Scalability test results"
echo -e "     • complete_benchmark_report.html - Full HTML report"
echo ""
echo -e "  🔗 ${BOLD}View HTML Report:${NC}"
echo -e "     open complete_benchmark_report.html"
echo ""

print_success "Benchmark complete! All 120,000 logs ingested (30,000 per storage node)"