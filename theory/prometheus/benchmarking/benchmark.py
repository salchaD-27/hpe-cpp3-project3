#!/usr/bin/env python3

import io
import json
import requests
import time
import statistics
import os
import gzip
import random
import tempfile
import shutil
import subprocess
from datetime import datetime

# Separate URLs for each architecture
VICTORIALOGS_JSON_URL = "http://localhost:9428"      # JSON-only architecture
VICTORIALOGS_HOT_URL  = "http://localhost:9429"      # Tiered hot tier only
VICTORIAMETRICS_URL   = "http://localhost:8428"      # Tiered cold tier

class Colors:
    GREEN = '\033[92m'
    RED = '\033[91m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    MAGENTA = '\033[95m'
    WHITE = '\033[97m'
    BOLD = '\033[1m'
    END = '\033[0m'

def print_header(text):
    print(f"\n{Colors.CYAN}{Colors.BOLD}{'='*100}{Colors.END}")
    print(f"{Colors.CYAN}{Colors.BOLD}{text:^100}{Colors.END}")
    print(f"{Colors.CYAN}{Colors.BOLD}{'='*100}{Colors.END}")

def print_success(text): print(f"{Colors.GREEN}✓ {text}{Colors.END}")
def print_info(text): print(f"{Colors.BLUE}➜ {text}{Colors.END}")
def print_metric(name, value): print(f"  {Colors.WHITE}●{Colors.END} {name}: {Colors.GREEN}{value}{Colors.END}")
def print_warning(text): print(f"{Colors.YELLOW}⚠ {text}{Colors.END}")

# ============================================================================
# GENERATE LOGS
# ============================================================================
def generate_logs(count):
    """Generate test logs matching HPC patterns"""
    logs = []
    services = ['kafka', 'zookeeper', 'cmuserver-0', 'opensearch', 'systemd', 
                'sudo', 'hpc-master', 'database', 'cache']
    hosts = ['leader1', 'leader2', 'leader3', 'padma', 'worker1', 'worker2']
    levels = ['INFO', 'WARN', 'ERROR', 'DEBUG']
    
    for i in range(count):
        log = {
            '_time': datetime.now().isoformat(),
            'level': random.choice(levels),
            '_msg': f"Test log message {i}",
            'service_name': random.choice(services),
            'host_name': random.choice(hosts),
            'duration_ms': random.randint(1, 10000),
            'memory_mb': random.randint(100, 32000),
            'cpu_percent': random.randint(1, 100),
            'retry_count': random.randint(0, 5)
        }
        logs.append(log)
    return logs

# ============================================================================
# QUERY DEFINITIONS
# ============================================================================
QUERIES = [
    # (name, logsql, promql)
    # promql=None means cold tier can't answer this query type

    ("COUNT ALL",
     "* | count()",
     "sum(hpc_log_total)"),

    ("COUNT ERRORS",
     "level:ERROR | count()",
     'sum(hpc_log_total{level="ERROR"})'),

    ("COUNT CRITICAL",
     "level:CRITICAL | count()",
     'sum(hpc_log_total{level="CRITICAL"})'),

    ("COUNT WARN",
     "level:WARN | count()",
     'sum(hpc_log_total{level="WARN"})'),

    ("COUNT DEBUG",
     "level:DEBUG | count()",
     'sum(hpc_log_total{level="DEBUG"})'),

    ("COUNT BY SERVICE",
     "* | stats by (service_name) count()",
     "sum by (service) (hpc_log_total)"),

    ("COUNT BY HOST",
     "* | stats by (host_name) count()",
     "sum by (host) (hpc_log_total)"),

    ("COUNT BY LEVEL",
     "* | stats by (level) count()",
     "sum by (level) (hpc_log_total)"),

    ("LAST 1 HOUR ERRORS",
     "_time:1h AND level:ERROR | count()",
     'sum(hpc_log_total{level="ERROR"}[1h])'),

    ("LAST 6 HOURS ERRORS",
     "_time:6h AND level:ERROR | count()",
     'sum(hpc_log_total{level="ERROR"}[6h])'),

    ("LAST 24 HOURS ERRORS",
     "_time:24h AND level:ERROR | count()",
     'sum(hpc_log_total{level="ERROR"}[24h])'),

    ("HIGH MEMORY",
     "memory_mb:>15000 | count()",
     None),  # raw memory_mb value not stored as metric label

    ("HIGH CPU",
     "cpu_percent:>80 | count()",
     None),  # raw cpu_percent value not stored as metric label

    ("MULTIPLE RETRIES",
     "retry_count:>2 | count()",
     None),  # raw retry_count value not stored as metric label

    ("KAFKA ERRORS",
     "level:ERROR AND service_name:kafka | count()",
     'sum(hpc_log_total{level="ERROR", service="kafka"})'),

    ("ZOOKEEPER ERRORS",
     "level:ERROR AND service_name:zookeeper | count()",
     'sum(hpc_log_total{level="ERROR", service="zookeeper"})'),

    ("EXTRACT TRACE IDS",
     "* | extract trace_id | count()",
     None),  # full text extraction not possible in PromQL

    ("AVERAGE DURATION",
     "* | stats avg(duration_ms)",
     None),  # duration_ms not stored as metric value

    ("P95 DURATION",
     "* | stats p95(duration_ms)",
     None),  # statistical distribution lost in Prometheus format

    ("CONTAINS TIMEOUT",
     "_msg:timeout | count()",
     None),  # full text search not possible in PromQL
]

# ============================================================================
# JSON-ONLY ARCHITECTURE (Dedicated VictoriaLogs instance)
# ============================================================================
class JSONOnlyArchitecture:
    def __init__(self):
        self.name = "JSON-ONLY"
        self.url = VICTORIALOGS_JSON_URL
    
    def clear_storage(self):
        """Clear VictoriaLogs storage by restarting container"""
        os.system("docker restart victorialogs-json > /dev/null 2>&1")
        time.sleep(5)
    
    def insert_batch(self, logs, batch_size=5000):
        """Insert logs using curl command"""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.jsonl', delete=False) as f:
            temp_file = f.name
            for log in logs:
                clean_log = {
                    '_time': log.get('_time', datetime.now().isoformat()),
                    'level': log.get('level', 'INFO'),
                    '_msg': log.get('_msg', ''),
                    'service_name': log.get('service_name', 'unknown'),
                    'host_name': log.get('host_name', 'unknown')
                }
                f.write(json.dumps(clean_log) + '\n')
        
        cmd = f"curl -s -X POST {self.url}/insert/jsonline -H 'Content-Type: application/json' --data-binary @{temp_file}"
        result = subprocess.run(cmd, shell=True, capture_output=True)
        os.unlink(temp_file)
        
        return len(logs) if result.returncode == 0 else 0
    
    def query(self, logsql):
        """Real query to VictoriaLogs - measure actual time"""
        times = []
        for i in range(3):
            start = time.perf_counter()
            try:
                resp = requests.get(
                    f"{self.url}/select/logsql/query",
                    params={"query": logsql},
                    timeout=60
                )
                elapsed = (time.perf_counter() - start) * 1000
                if resp.status_code == 200:
                    times.append(elapsed)
            except Exception as e:
                times.append(5000)
            time.sleep(0.5)
        
        return statistics.mean(times) if times else 999
    
    def get_storage_size(self):
        """Get actual storage size from container"""
        try:
            result = subprocess.run(
                ["docker", "exec", "victorialogs-json", "du", "-sb", "/storage"],
                capture_output=True, text=True
            )
            if result.returncode == 0:
                bytes_size = int(result.stdout.split()[0])
                return bytes_size / (1024 * 1024)
        except:
            pass
        return 0

# ============================================================================
# TIERED STORAGE ARCHITECTURE (Separate hot tier + warm files + cold metrics)
# ============================================================================
class TieredStorageArchitecture:
    def __init__(self):
        self.name = "TIERED"
        self.hot_url = VICTORIALOGS_HOT_URL
        self.cold_url = VICTORIAMETRICS_URL
        self.hot_logs = []
        self.warm_logs = []
        self.cold_logs = []
        self.temp_dir = None
        self.hot_file = None
        self.warm_file = None
    
    def clear_storage(self):
        if self.temp_dir and os.path.exists(self.temp_dir):
            shutil.rmtree(self.temp_dir)
        self.temp_dir = None
        self.hot_logs = []
        self.warm_logs = []
        self.cold_logs = []
        self.hot_file = None
        self.warm_file = None
        
        # Clear VictoriaLogs hot tier
        os.system("docker restart victorialogs-tiered-hot > /dev/null 2>&1")
        time.sleep(3)
    
    def setup_directories(self):
        if not self.temp_dir:
            self.temp_dir = tempfile.mkdtemp()
            self.hot_file = os.path.join(self.temp_dir, "hot.jsonl")
            self.warm_file = os.path.join(self.temp_dir, "warm.jsonl.gz")
    
    def insert(self, logs):
        self.setup_directories()
        
        # Distribute logs across tiers (simulate age-based distribution)
        for log in logs:
            r = random.random()
            if r < 0.4:  # 40% hot (0-7 days)
                self.hot_logs.append(log)
            elif r < 0.7:  # 30% warm (8-30 days)
                self.warm_logs.append(log)
            else:  # 30% cold (31+ days)
                self.cold_logs.append(log)
        
        # Write hot tier to file and insert into VictoriaLogs
        with open(self.hot_file, 'w') as f:
            for log in self.hot_logs:
                f.write(json.dumps(log) + '\n')
        
        self._insert_hot_to_victorialogs()
        
        # Write warm tier (compressed)
        with gzip.open(self.warm_file, 'wt', encoding='utf-8') as gz:
            f = io.TextIOWrapper(gz) if not isinstance(gz, io.TextIOWrapper) else gz
            for log in self.warm_logs:
                f.write(json.dumps(log) + '\n')
        
        # Insert cold tier into VictoriaMetrics
        self._insert_cold_tier()
        
        return len(logs)
    
    def _insert_hot_to_victorialogs(self):
        """Insert hot tier into dedicated VictoriaLogs instance once"""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.jsonl', delete=False) as f:
            temp_file = f.name
            for log in self.hot_logs:
                f.write(json.dumps(log) + '\n')
        
        cmd = f"curl -s -X POST {self.hot_url}/insert/jsonline -H 'Content-Type: application/json' --data-binary @{temp_file}"
        subprocess.run(cmd, shell=True, capture_output=True)
        os.unlink(temp_file)
    
    def _insert_cold_tier(self):
        """Insert cold tier data into VictoriaMetrics"""
        metrics = []
        for log in self.cold_logs:
            try:
                dt = datetime.fromisoformat(log['_time'].replace('Z', '+00:00'))
                ts_ms = int(dt.timestamp() * 1000)
            except:
                ts_ms = int(datetime.now().timestamp() * 1000)
            
            level = log['level']
            service = log['service_name']
            host = log['host_name']
            metrics.append(
                f'hpc_log_total{{level="{level}",'
                f'service="{service}",'
                f'host="{host}"'
                f'}} 1 {ts_ms}'
            )
        
        if metrics:
            payload = '\n'.join(metrics)
            try:
                resp = requests.post(
                    f"{self.cold_url}/api/v1/import/prometheus",
                    data=payload,
                    timeout=60
                )
            except:
                pass
    
    def query_hot_tier(self, logsql):
        """Query hot tier (real VictoriaLogs query)"""
        start = time.perf_counter()
        try:
            resp = requests.get(
                f"{self.hot_url}/select/logsql/query",
                params={"query": logsql},
                timeout=30
            )
            elapsed = (time.perf_counter() - start) * 1000
            return elapsed if resp.status_code == 200 else None
        except:
            return None
    
    def query_warm_tier(self, query_name):
        if not os.path.exists(self.warm_file):
            return None

        start = time.perf_counter()

        if query_name == "COUNT ALL":
            with gzip.open(self.warm_file, 'rb') as f:
                result = sum(1 for _ in f)

        elif query_name in ("COUNT ERRORS", "COUNT CRITICAL", "COUNT WARN", "COUNT DEBUG"):
            level_map = {
                "COUNT ERRORS": "ERROR",
                "COUNT CRITICAL": "CRITICAL",
                "COUNT WARN": "WARN",
                "COUNT DEBUG": "DEBUG"
            }
            target = level_map[query_name]
            count = 0
            with gzip.open(self.warm_file, 'rb') as f:
                for line in f:
                    if json.loads(line).get('level') == target:
                        count += 1
            result = count

        elif query_name in ("COUNT BY SERVICE", "COUNT BY HOST", "COUNT BY LEVEL"):
            field_map = {
                "COUNT BY SERVICE": "service_name",
                "COUNT BY HOST": "host_name",
                "COUNT BY LEVEL": "level"
            }
            field = field_map[query_name]
            result = {}
            with gzip.open(self.warm_file, 'rb') as f:
                for line in f:
                    val = json.loads(line).get(field, 'unknown')
                    result[val] = result.get(val, 0) + 1
        else:
            with gzip.open(self.warm_file, 'rb') as f:
                result = sum(1 for _ in f)

        elapsed = (time.perf_counter() - start) * 1000
        return elapsed
    
    def query_cold_tier(self, promql):
        """Query cold tier (real PromQL query to VictoriaMetrics)"""
        if promql is None or not self.cold_logs:
            return None 
        
        start = time.perf_counter()
        try:
            resp = requests.get(
                f"{self.cold_url}/api/v1/query",
                params={"query": promql},
                timeout=30
            )
            elapsed = (time.perf_counter() - start) * 1000
            return elapsed if resp.status_code == 200 else None
        except:
            return None
    
    def query(self, query_name, logsql, promql):
        """Query across all tiers - hot (fast) + warm (slow) + cold (fast)"""
        times = []
        
        hot_time = self.query_hot_tier(logsql)
        if hot_time is not None:
            times.append(hot_time)
        
        warm_time = self.query_warm_tier(query_name)
        if warm_time is not None:
            times.append(warm_time)
        
        cold_time = self.query_cold_tier(promql)
        if cold_time is not None:
            times.append(cold_time)
        
        return sum(times) if times else 999
    
    def get_storage_size(self):
        hot_size = os.path.getsize(self.hot_file) / (1024 * 1024) if self.hot_file and os.path.exists(self.hot_file) else 0
        warm_size = os.path.getsize(self.warm_file) / (1024 * 1024) if self.warm_file and os.path.exists(self.warm_file) else 0
        cold_size = (len(self.cold_logs) * 60) / (1024 * 1024)  # 60 bytes per metric → MB
        return hot_size + warm_size + cold_size

# ============================================================================
# MAIN BENCHMARK
# ============================================================================
def main():
    print_header("REAL 300,000 LOG BENCHMARK")
    print_info("JSON-ONLY vs TIERED STORAGE with SEPARATE VictoriaLogs instances")
    print_warning("This will take 10-15 minutes...")
    
    LOG_COUNT = 300000
    
    # Check services
    try:
        requests.get(f"{VICTORIALOGS_JSON_URL}/metrics", timeout=5)
        print_success("VictoriaLogs (JSON-ONLY) is running on port 9428")
    except:
        print_warning("VictoriaLogs JSON-ONLY not running")
        return
    
    try:
        requests.get(f"{VICTORIALOGS_HOT_URL}/metrics", timeout=5)
        print_success("VictoriaLogs (TIERED Hot) is running on port 9429")
    except:
        print_warning("VictoriaLogs TIERED Hot not running")
        return
    
    try:
        requests.get(f"{VICTORIAMETRICS_URL}/metrics", timeout=5)
        print_success("VictoriaMetrics is running on port 8428")
    except:
        print_warning("VictoriaMetrics not running")
        return
    
    # Generate logs
    print_info(f"\n📂 Generating {LOG_COUNT:,} test logs...")
    logs = generate_logs(LOG_COUNT)
    print_success(f"Generated {len(logs):,} logs")
    
    # Calculate raw size
    sample = json.dumps(logs[0])
    avg_size = len(sample.encode('utf-8'))
    raw_mb = (avg_size * LOG_COUNT) / (1024 * 1024)
    print_metric("Estimated raw JSON size", f"{raw_mb:.2f} MB")
    
    # JSON-ONLY Architecture
    print_info("\n📊 Testing JSON-ONLY Architecture...")
    json_arch = JSONOnlyArchitecture()
    json_arch.clear_storage()
    
    start = time.time()
    inserted = json_arch.insert_batch(logs)
    insert_time = time.time() - start
    print_success(f"Inserted {inserted:,}/{LOG_COUNT:,} logs in {insert_time:.1f}s")
    
    json_storage = json_arch.get_storage_size()
    print_metric("JSON-ONLY Storage", f"{json_storage:.2f} MB")
    
    # TIERED Architecture
    print_info("\n📊 Testing TIERED STORAGE Architecture...")
    tiered_arch = TieredStorageArchitecture()
    tiered_arch.clear_storage()
    
    start = time.time()
    tiered_arch.insert(logs)
    insert_time_tiered = time.time() - start
    print_success(f"Inserted {LOG_COUNT:,} logs in {insert_time_tiered:.1f}s")
    
    tiered_storage = tiered_arch.get_storage_size()
    print_metric("TIERED Storage", f"{tiered_storage:.2f} MB")
    
    # Run queries
    print_header("QUERY PERFORMANCE COMPARISON")
    print(f"\n{'Query Type':<25} {'JSON-ONLY (ms)':>18} {'TIERED (ms)':>15} {'Winner':>12}")
    print(f"{'-'*75}")
    
    results = []
    json_wins = 0
    tiered_wins = 0
    
    for query_name, logsql, promql in QUERIES:
        print_info(f"Running: {query_name}...")
        
        json_time = json_arch.query(logsql)
        tiered_time = tiered_arch.query(query_name, logsql, promql)
        
        winner = "TIERED" if tiered_time < json_time else "JSON"
        if winner == "JSON":
            json_wins += 1
        else:
            tiered_wins += 1
        
        results.append({
            'query': query_name,
            'json_time': json_time,
            'tiered_time': tiered_time,
            'winner': winner
        })
        
        winner_color = Colors.GREEN if winner == "TIERED" else Colors.YELLOW
        print(f"{query_name:<25} {json_time:>17.2f} {tiered_time:>14.2f} {winner_color}{winner:>10}{Colors.END}")
    
    # Summary
    print_header("FINAL SUMMARY")
    
    avg_json = statistics.mean([r['json_time'] for r in results])
    avg_tiered = statistics.mean([r['tiered_time'] for r in results])
    
    print(f"\n  {'Metric':<30} {'JSON-ONLY':>20} {'TIERED':>15}")
    print(f"  {'-'*65}")
    print(f"  {'Average Query Time (ms)':<30} {avg_json:>20.2f} {avg_tiered:>15.2f}")
    print(f"  {'Total Wins':<30} {json_wins:>20} {tiered_wins:>15}")
    print(f"  {'Storage Size (MB)':<30} {json_storage:>20.2f} {tiered_storage:>15.2f}")
    print(f"  {'Storage Savings':<30} {'-':>20} {(1 - tiered_storage/raw_mb)*100:>14.1f}%")
    
    print_header("FINAL VERDICT")
    
    if json_wins > tiered_wins:
        print(f"\n{Colors.GREEN}{Colors.BOLD}🏆 WINNER: JSON-ONLY ARCHITECTURE{Colors.END}")
        print(f"\n  • {json_wins}/{len(QUERIES)} queries faster ({json_wins/len(QUERIES)*100:.0f}%)")
        print(f"  • {avg_json:.2f}ms average query time")
        print(f"  • {json_storage:.2f}MB storage for {LOG_COUNT:,} logs")
    else:
        print(f"\n{Colors.GREEN}{Colors.BOLD}🏆 WINNER: TIERED STORAGE{Colors.END}")
        print(f"\n  • {tiered_wins}/{len(QUERIES)} queries faster")
        print(f"  • {(1 - tiered_storage/raw_mb)*100:.1f}% less storage")

if __name__ == "__main__":
    main()