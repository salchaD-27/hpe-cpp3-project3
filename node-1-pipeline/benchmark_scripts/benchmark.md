# Benchmarking Introduction

Benchmarking query results evaluates how fast and accurately a database or search engine processes specific workloads. It identifies performance bottlenecks, measures response times, and verifies output accuracy against expected benchmarks.

## Key Performance Metrics

* *Latency*: The time needed to process a single query.
* *Throughput*: The number of queries handled per second (QPS).
* *P95/P99 Percentiles*: The maximum latency experienced by 95% or 99% of users.
* *Resource Utilization*: Tracking CPU, memory, and disk I/O during execution.
* *Recall/Precision*: Measuring how well search queries retrieve relevant, accurate results.

## Common Benchmarking Tools

* *Sysbench*: Standard tool for OLTP relational databases.
* *HammerDB*: Load testing tool for enterprise databases.
* *YCSB*: Benchmark for NoSQL and cloud database systems.

## Best Practices for Benchmarking

* *Isolate variables*: Test only one configuration or query change at a time.
* *Run multiple iterations*: Average the execution times to account for caching and system noise.
* *Simulate concurrency*: Mimic real-world user traffic to stress the system.
* *Warm the cache*: Run preliminary queries to load data into memory before measuring.

```
For example, when analyzing time-series datasets, engineers compare InfluxDB or Cassandra throughput. When benchmarking precision in information retrieval, results are often compared against manually verified clinical or bibliographic datasets. To dive deeper, you can review time-series Time Series Databases and InfluxDB methodologies.(https://cs.ulb.ac.be/public/_media/teaching/influxdb_2017.pdf)
```

# Benchmarking with VictoriaLogs

VictoriaLogs excels in read-heavy log analysis workloads, demonstrating up to *94% lower query latency* and *36% higher query throughput* compared to Grafana Loki under intensive concurrent read stress. Because it implements a `columnar log engine` with `per-field indexing`, it avoids the heavy full-scan regex constraints typical of label-only indexing systems.

To support massive read scaling while maintaining constant ingestion firehoses, decouple storage layouts and data structures:

* *Explicit Stream Fields vs. Other Fields*: Ensure high-cardinality metadata (like  `trace_id`, `ip`, or `user_id`) is stored in individual "other fields" instead of bundling everything inside a generic unstructured `_msg` field. VictoriaLogs handles structured per-field tracking automatically, preventing expensive substring parsing over standard fields at read time.
* *Avoid Dynamic Extraction*: Do not ingest flat strings and parse them dynamically via `| extract ...` at query time. Structuring your JSON logs prior to ingestion enables instantaneous filter executions over exact indices.
* *Leverage Recording Rules*: For recurring visualization dashboards (e.g., Grafana), use `vmalert` recording rules to pre-aggregate log metrics into time series. Querying raw, unaggregated logs over massive historical time slots forces heavy disk scans that can hit hardware bottlenecks under high concurrency.

## Benchmarking Framework for VictoriaLogs

To mock an enterprise read-heavy analytical workload, use a modern HTTP load generator capable of sustaining thousands of concurrent REST calls.

* Load Testing Tooling : Since VictoriaLogs evaluates LogsQL queries via standard HTTP endpoints (like /select/logsql/query), Locust or k6 are the ideal benchmarking tools.
* *Sample k6 Test Implementation* : Save this test configuration script (`individual_query_perf.js`) to target your endpoint under a ramp-up user workload.

## Metrics to Monitor During the Benchmark

While running your read workload concurrent with your production log ingestion pipelines, track the following internal metrics via Prometheus scraping:

| Prometheus Metric Name | Critical Monitoring Purpose | Target State |
| -------------------- | -------------------- | -------------------- |
| *vl_slow_queries_total* | Count of queries that exceeded your low duration threshold | Keep close to 0 |
| *vl_rows_dropped_total* | Dropped ingestion log items due to timestamps out of retention limits | Should be 0 |
| *process_cpu_seconds_total* | System processing units allocated to handle execution lines | Avoid hitting 100% throttling |
| *process_resident_memory_bytes* | Real heap memory consumed by storage blocks and indexes | Stable; check for memory leaks |

# Client-Side Benchmark Metrics(Query-level)

In addition to server-side Prometheus metrics, the benchmark harness should collect client-observed performance metrics. These measurements reflect the experience of users and applications issuing LogsQL queries against VictoriaLogs.

## Benchmarking Frameworks

1. k6

*k6* is a modern load-testing framework written in *Go* that uses *JavaScript* for test definitions.

-Advantages

* Lightweight and easy to deploy
* Excellent concurrency support
* Native latency percentile reporting
* Suitable for CI/CD pipelines
* Minimal resource consumption on the load generator
* Example Use Cases
* Dashboard query benchmarking
* API stress testing
* Throughput testing
* Query latency validation

* Example request:

```js
import http from 'k6/http';

export default function () {
    http.get(
        'http://localhost:9428/select/logsql/query?query=*'
    );
}
```

2. Locust

*Locust* is a *Python-based* load-testing framework that allows user behavior modeling through Python code.

-Advantages

* Easy to customize complex workflows
* Supports distributed execution
* Web-based monitoring interface
* Flexible workload generation
* Example Use Cases
* Simulating multiple user personas
* End-to-end observability workflow testing
* Large-scale concurrency testing

* Example request:

```python
from locust import HttpUser, task

class QueryUser(HttpUser):

    @task
    def run_query(self):
        self.client.get(
            "/select/logsql/query",
            params={"query": "*"}
        )
```

3. Python Requests + ThreadPoolExecutor

For targeted benchmarking and custom metric collection, a lightweight *Python* benchmark harness can be implemented using:

```bash
requests
concurrent.futures.ThreadPoolExecutor
```

-Advantages
* Full control over benchmark logic
* Easy integration with custom metrics
* Minimal dependencies
* Ideal for query-by-query analysis

* Example:

```python
response = requests.get(
    "http://localhost:9428/select/logsql/query",
    params={"query": query}
)
```

## Query Latency Metrics

Latency measures the time required for VictoriaLogs to receive, execute, and return a query response.

### Average Latency

The arithmetic mean of all observed request durations.

**Purpose**  

* Provides a general view of query responsiveness.
* Useful for comparing different query implementations.
* Can be skewed by a small number of very slow requests.

```text
Average Latency = Sum(All Request Latencies) / Total Requests
```

### Minimum Latency

The fastest observed query execution.

**Purpose**  

* Represents the best-case performance.
* Useful for identifying cache-hit behavior.

### Maximum Latency

The slowest observed query execution.

**Purpose**  

* Identifies worst-case behavior.
* Helps detect sporadic slow queries and resource contention.

### P50 Latency (Median)

The latency below which 50% of requests complete.

**Purpose**  

* Represents the typical user experience.
* Less affected by outliers than the average.

### P95 Latency

The latency below which 95% of requests complete.

**Purpose**  

* Measures tail latency.
* Frequently used in service-level objectives (SLOs).
* Helps identify occasional slow query execution.

### P99 Latency

The latency below which 99% of requests complete.

**Purpose**  

* Captures extreme outliers.
* Useful for evaluating production readiness under load.

### Latency Standard Deviation

Measures how much latency varies around the average.

**Purpose**  

* Indicates response-time stability.
* Lower values indicate more predictable performance.
* High values suggest resource contention, cache effects, or inconsistent query execution.

---

## Throughput Metrics

### Queries Per Second (QPS)

The number of completed queries divided by benchmark duration.

```text
QPS = Total Requests / Benchmark Duration
```

**Purpose**  

* Measures overall system capacity.
* Indicates how many concurrent analytical requests VictoriaLogs can sustain.

### Requests Per Worker

The average number of requests executed by each benchmark worker thread.

```text
Requests Per Worker = Total Requests / Number of Workers
```

**Purpose**  

* Helps evaluate load distribution.
* Useful when comparing different concurrency levels.

---

## Reliability Metrics

### Success Count

Number of requests returning HTTP 200 responses.

**Purpose**  

* Measures successful query execution.

### Failure Count

Number of requests returning non-200 responses.

**Purpose**  

* Identifies syntax errors, backend failures, timeouts, and resource exhaustion.

### Success Rate

```text
Success Rate (%) =
(Successful Requests / Total Requests) × 100
```

**Purpose**  

* Indicates overall system reliability under load.

### Failure Rate

```text
Failure Rate (%) =
(Failed Requests / Total Requests) × 100
```

**Purpose**  

* Helps determine the point at which system saturation begins.

### HTTP Status Code Distribution

Tracks counts of each returned status code.

Example:

```text
200 : 1240
400 : 15
500 : 3
503 : 8
```

**Purpose**  

* Identifies the nature of failures.
* Distinguishes query syntax errors from infrastructure issues.

### Timeout Count

Number of requests exceeding the configured client timeout.

**Purpose**  

* Detects backend stalls and overload conditions.
* Useful for identifying long-running aggregations.

---

## Response Payload Metrics

### Average Response Size

Average response payload returned by VictoriaLogs.

```text
Average Response Size =
Total Response Bytes / Total Requests
```

**Purpose**  

* Measures network transfer overhead.
* Useful when benchmarking aggregation-heavy queries.

### Maximum Response Size

Largest response returned during testing.

**Purpose**  

* Identifies queries generating excessive result sets.

### Total Downloaded Data

Total response bytes received during the benchmark.

**Purpose**  

* Measures overall network consumption.

### Data Throughput

```text
Data Throughput =
Total Downloaded Bytes / Benchmark Duration
```

Typically reported as MB/s.

**Purpose**  

* Measures effective data transfer rate during query execution.

---

## Slow Query Metrics

### Slow Query Count (>1s, >2s, >5s)

Counts requests exceeding predefined latency thresholds.

Example:

```text
Queries >1s : 124
Queries >2s : 37
Queries >5s : 4
```

**Purpose**  

* Quickly identifies problematic workloads.
* Useful when correlating benchmark results with VictoriaLogs slow-query logs.

---

## Scalability Metrics

### Concurrency Scaling Efficiency

Measures how effectively throughput increases as worker count grows.

```text
Scaling Efficiency =
Observed QPS /
(Single Worker QPS × Worker Count)
```

Example:

```text
1 Worker  = 5 QPS
5 Workers = 23 QPS

Efficiency = 23 / (5 × 5)
           = 92%
```

**Purpose**  

* Quantifies lock contention and resource bottlenecks.
* Indicates whether the system scales linearly.

### Peak Concurrent Requests

Maximum number of simultaneously active requests observed during testing.

**Purpose**  

* Validates that the intended concurrency level was achieved.
* Helps correlate performance degradation with concurrency.

---

## Resource Utilization Metrics

These metrics should be collected alongside benchmark execution using Docker, cAdvisor, or Prometheus.

### CPU Utilization

Measures processor consumption during query execution.

**Purpose**  

* Identifies CPU-bound workloads.
* Highlights expensive operators such as aggregation, regex matching, and grouping.

### Memory Utilization

Tracks resident memory consumption.

**Purpose**  

* Detects excessive aggregation cardinality.
* Helps identify memory leaks and OOM risk.

### Peak Memory Usage

Highest observed memory consumption.

**Purpose**  

* Particularly important for high-cardinality operations such as:

```logsql
| stats by (formatted)
```

### Disk I/O

Measures storage activity during execution.

**Purpose**  

* Identifies queries requiring large historical scans.
* Helps determine whether storage throughput is limiting performance.

---

## Cold Cache vs Warm Cache Performance

### Cold Query Latency

Latency of the first execution after startup or cache invalidation.

**Purpose**  

* Represents worst-case user experience.

### Warm Query Latency

Latency after data structures, indexes, and filesystem pages are cached.

**Purpose**  

* Represents steady-state production performance.

Comparing cold and warm executions helps quantify cache effectiveness and index utilization.

# Benchmarking vmalert rule file

To benchmark the performance of an entire vmalert rule file—rather than a single isolated query—you need to evaluate how efficiently vmalert processes the entire batch of rules under real or simulated log volume.
When running multiple rules, the primary performance bottlenecks are CPU saturation (from processing expressions), memory growth (from tracking alert states), and datasource execution delays (if VictoriaLogs cannot keep up with concurrent requests).

## Key Metrics to Monitor for Rule Benchmarking

* VictoriaLogs and `vmalert` expose standard Prometheus metrics at their `/metrics` endpoints. Scraping these during a benchmark run gives you exact performance data.
* *vmalert Processing Metricsvmalert_iteration_duration_seconds* : This is the most critical metric. It measures how long it takes to execute all rules in a group. *Benchmark Goal*: The maximum duration must be significantly lower than your interval (e.g., if your `interval` is `30s`, execution should take `< 5s`).
* *vmalert_iteration_total & vmalert_iteration_missed_total* : If `vmalert_iteration_missed_total` starts increasing, it means your rule file is too heavy, and `vmalert` is skipping execution windows because the previous loop hasn't finished.
* *vmalert_execution_errors_total* : Tracks if queries inside your `.yml` file are failing due to syntax errors or backend timeouts during the test.

## System Resource Metrics (via Prometheus Node Exporter / cAdvisor)

* *process_cpu_seconds_total (for vmalert)* : Measures the exact CPU core usage dedicated to executing those rules. A steep spike during execution loops indicates computationally heavy LogsQL queries (like heavy text regex patterns).
* *process_resident_memory_bytes (for vmalert)* : Tracks memory allocation. vmalert stays lightweight, but tracking thousands of concurrent active alert states over long for: 2h windows will cause this to step upward.

## Step-by-Step Benchmarking Methodology

To truly benchmark the rule file, you should test it under a realistic "worst-case scenario"—such as a high-error incident where many alerts fire simultaneously.

* Step 1: Isolate the Test EnvironmentDo not run this on production. Set up a dedicated testing container instance of vmalert pointed to a staging VictoriaLogs instance containing your sample 100 logs/sec stream.
* Step 2: Configure a High-Frequency Stress TestTemporarily modify your target alert `.yml` file to execute at an unrealistically high frequency. This compresses hours of production scheduling into a few minutes of heavy stress testing.Reduce the group interval to `5s` or `1s`.Reduce your rule for durations (e.g., change `for`: `15m` to `for`: `10s`) to force alerts into `PENDING` and `FIRING` states rapidly.

test-alerts.yml

```yml
groups:
  - name: benchmark_group
    interval: 2s # Aggressive interval to stress test evaluation speed
    rules:
      - alert: HighHttp5xxErrorRate
        expr: '_stream:{environment="prod"} AND _time:5m AND status:500 | stats count(*) as total'
        for: 5s 
        labels:
          severity: critical
```

* Step 3: Spin Up vmalert with Metrics EnabledLaunch vmalert with the rule file and ensure the metrics port is active (default is `:8880`):

``` bash
/path/to/vmalert \
  -rule=/path/to/test-alerts.yml \
  -datasource.url=http://victorialogs-host:9428 \
  -notifier.url=http://localhost:9093 \
  -httpListenAddr=:8880
```

* Step 4: *Run the Simulation and Fetch the Metrics* : While your logs simulator runs at `100 logs/sec` (or higher to simulate a log storm), let the rules execute for `10–15 minutes`. You can query the raw benchmark data instantly using curl against the metrics endpoint to see how long the execution loop took:

```bash
curl -s http://localhost:8880/metrics | grep vmalert_iteration_duration_seconds
```

Look specifically for the quantiles in the output:
    *vmalert_iteration_duration_seconds*{quantile="`0.99`"}: Tells you the maximum time it took to evaluate the entire file for `99%` of the loops. If this number approaches or exceeds your group interval, your rule file will degrade system performance.

## Automated Performance Validation via vmalert-tool

Before even deploying the file to a system running live resource monitors, you can validate the analytical correctness and syntax execution speed of your rule file using VictoriaMetrics' native CLI tool:

```bash
vmalert-tool test -rule=/path/to/test-alerts.yml`
```

This structural unit-test approach ensures your rules do not contain cross-referencing logic errors or looping bugs that block system threads before you subject your infrastructure to live parsing stress.
