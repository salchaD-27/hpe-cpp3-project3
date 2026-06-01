#!/usr/bin/env python3
"""
Benchmarking Middleware for JSON vs Hybrid Storage Comparison
Queries both storage types and compares performance metrics
"""

from flask import Flask, request, jsonify
import requests
import time
import json
from datetime import datetime
from collections import defaultdict
import threading
import statistics
import os

app = Flask(__name__)

# Configuration from environment variables
JSON_NODES = os.environ.get('JSON_NODES', 'node-3-vlstorage:9428,node-4-vlstorage:9428').split(',')
HYBRID_NODES = os.environ.get('HYBRID_NODES', 'node-3-vlstorage-hybrid:9428,node-4-vlstorage-hybrid:9428').split(',')

# Add http:// prefix
JSON_NODES = [f"http://{node}" for node in JSON_NODES]
HYBRID_NODES = [f"http://{node}" for node in HYBRID_NODES]

# Metrics storage
benchmark_results = {
    "json": {"query_times": [], "result_counts": [], "timestamps": []},
    "hybrid": {"query_times": [], "result_counts": [], "timestamps": []}
}

class StorageBenchmark:
    def __init__(self):
        self.total_queries = 0
        
    def query_node(self, url, query):
        """Query a single storage node and measure time"""
        start = time.time()
        try:
            response = requests.get(
                f"{url}/select/logsql/query", 
                params={"query": query}, 
                timeout=30
            )
            elapsed = (time.time() - start) * 1000  # Convert to ms
            return {
                "success": response.status_code == 200,
                "time_ms": elapsed,
                "data": response.json() if response.status_code == 200 else None,
                "size_bytes": len(response.content),
                "status_code": response.status_code
            }
        except Exception as e:
            elapsed = (time.time() - start) * 1000
            return {
                "success": False, 
                "error": str(e), 
                "time_ms": elapsed,
                "status_code": 500
            }
    
    def query_storage_type(self, nodes, query):
        """Query all nodes of a specific storage type"""
        results = []
        for node in nodes:
            result = self.query_node(node, query)
            result["node"] = node
            results.append(result)
        return results
    
    def get_aggregate_results(self, results):
        """Aggregate results from multiple nodes"""
        successful = [r for r in results if r["success"]]
        if not successful:
            return {
                "success": False,
                "avg_time_ms": 0,
                "total_results": 0,
                "nodes_responded": 0,
                "errors": [r.get("error") for r in results if not r["success"]]
            }
        
        # Merge data from all successful nodes
        merged_data = {}
        total_results = 0
        for r in successful:
            if r["data"]:
                if isinstance(r["data"], dict):
                    for key, value in r["data"].items():
                        if key not in merged_data:
                            merged_data[key] = 0
                        if isinstance(value, (int, float)):
                            merged_data[key] += value
                        total_results += 1
        
        return {
            "success": True,
            "avg_time_ms": statistics.mean([r["time_ms"] for r in successful]),
            "min_time_ms": min([r["time_ms"] for r in successful]),
            "max_time_ms": max([r["time_ms"] for r in successful]),
            "total_results": total_results,
            "nodes_responded": len(successful),
            "total_nodes": len(results),
            "merged_data": merged_data
        }
    
    def compare_formats(self, query, iterations=5):
        """Compare JSON vs Hybrid storage for a specific query"""
        json_times = []
        hybrid_times = []
        json_counts = []
        hybrid_counts = []
        json_errors = 0
        hybrid_errors = 0
        
        for i in range(iterations):
            # Query JSON nodes
            json_results = self.query_storage_type(JSON_NODES, query)
            json_agg = self.get_aggregate_results(json_results)
            if json_agg["success"]:
                json_times.append(json_agg["avg_time_ms"])
                json_counts.append(json_agg["total_results"])
            else:
                json_errors += 1
            
            # Query Hybrid nodes
            hybrid_results = self.query_storage_type(HYBRID_NODES, query)
            hybrid_agg = self.get_aggregate_results(hybrid_results)
            if hybrid_agg["success"]:
                hybrid_times.append(hybrid_agg["avg_time_ms"])
                hybrid_counts.append(hybrid_agg["total_results"])
            else:
                hybrid_errors += 1
            
            # Small delay between iterations
            time.sleep(0.5)
        
        result = {
            "query": query,
            "iterations": iterations,
            "json": {
                "avg_time_ms": statistics.mean(json_times) if json_times else 0,
                "p95_time_ms": self._percentile(json_times, 95) if json_times else 0,
                "avg_result_count": statistics.mean(json_counts) if json_counts else 0,
                "success_rate": ((iterations - json_errors) / iterations) * 100,
                "samples": len(json_times)
            },
            "hybrid": {
                "avg_time_ms": statistics.mean(hybrid_times) if hybrid_times else 0,
                "p95_time_ms": self._percentile(hybrid_times, 95) if hybrid_times else 0,
                "avg_result_count": statistics.mean(hybrid_counts) if hybrid_counts else 0,
                "success_rate": ((iterations - hybrid_errors) / iterations) * 100,
                "samples": len(hybrid_times)
            }
        }
        
        # Calculate comparison metrics
        if result["json"]["avg_time_ms"] > 0 and result["hybrid"]["avg_time_ms"] > 0:
            result["comparison"] = {
                "speedup_ratio": result["json"]["avg_time_ms"] / result["hybrid"]["avg_time_ms"],
                "speedup_percent": (1 - result["hybrid"]["avg_time_ms"] / result["json"]["avg_time_ms"]) * 100,
                "winner": "Hybrid" if result["hybrid"]["avg_time_ms"] < result["json"]["avg_time_ms"] else "JSON",
                "time_difference_ms": abs(result["json"]["avg_time_ms"] - result["hybrid"]["avg_time_ms"])
            }
        else:
            result["comparison"] = {
                "speedup_ratio": 0,
                "speedup_percent": 0,
                "winner": "Unknown",
                "time_difference_ms": 0
            }
        
        return result
    
    def _percentile(self, data, percentile):
        """Calculate percentile of a list"""
        if not data:
            return 0
        sorted_data = sorted(data)
        index = int(len(sorted_data) * percentile / 100)
        return sorted_data[min(index, len(sorted_data) - 1)]

benchmark = StorageBenchmark()

@app.route('/api/compare', methods=['POST'])
def compare_storage():
    """Compare JSON vs Hybrid storage for a query"""
    data = request.json
    query = data.get('query', '* | count()')
    iterations = data.get('iterations', 5)
    
    result = benchmark.compare_formats(query, iterations)
    
    # Store for history
    benchmark_results["json"]["query_times"].append(result["json"]["avg_time_ms"])
    benchmark_results["hybrid"]["query_times"].append(result["hybrid"]["avg_time_ms"])
    benchmark_results["json"]["timestamps"].append(datetime.now().isoformat())
    benchmark_results["hybrid"]["timestamps"].append(datetime.now().isoformat())
    
    # Keep only last 100 entries
    for key in benchmark_results:
        for field in benchmark_results[key]:
            if len(benchmark_results[key][field]) > 100:
                benchmark_results[key][field] = benchmark_results[key][field][-100:]
    
    return jsonify(result)

@app.route('/api/benchmark/suite', methods=['POST'])
def run_benchmark_suite():
    """Run a complete benchmark suite with multiple queries"""
    data = request.json
    queries = data.get('queries', [
        "* | count()",
        "level:ERROR | count()",
        "* | stats by (service_name) count()",
        "_time:1h AND level:ERROR | count()",
        "* | filter level:ERROR | limit 100"
    ])
    iterations = data.get('iterations', 3)
    
    results = {}
    for query in queries:
        results[query] = benchmark.compare_formats(query, iterations)
    
    # Calculate overall summary
    json_avg_time = statistics.mean([r["json"]["avg_time_ms"] for r in results.values() if r["json"]["avg_time_ms"] > 0])
    hybrid_avg_time = statistics.mean([r["hybrid"]["avg_time_ms"] for r in results.values() if r["hybrid"]["avg_time_ms"] > 0])
    
    return jsonify({
        "timestamp": datetime.now().isoformat(),
        "queries_tested": len(queries),
        "iterations_per_query": iterations,
        "results": results,
        "summary": {
            "json_avg_time_ms": json_avg_time,
            "hybrid_avg_time_ms": hybrid_avg_time,
            "overall_speedup": (1 - hybrid_avg_time / json_avg_time) * 100 if json_avg_time > 0 else 0,
            "overall_winner": "Hybrid" if hybrid_avg_time < json_avg_time else "JSON"
        }
    })

@app.route('/api/benchmark/history', methods=['GET'])
def get_benchmark_history():
    """Get historical benchmark results"""
    return jsonify({
        "json": {
            "avg_query_time_ms": statistics.mean(benchmark_results["json"]["query_times"]) if benchmark_results["json"]["query_times"] else 0,
            "samples": len(benchmark_results["json"]["query_times"])
        },
        "hybrid": {
            "avg_query_time_ms": statistics.mean(benchmark_results["hybrid"]["query_times"]) if benchmark_results["hybrid"]["query_times"] else 0,
            "samples": len(benchmark_results["hybrid"]["query_times"])
        },
        "recent": {
            "json_last_10": benchmark_results["json"]["query_times"][-10:],
            "hybrid_last_10": benchmark_results["hybrid"]["query_times"][-10:]
        }
    })

@app.route('/api/storage/status', methods=['GET'])
def get_storage_status():
    """Check health of all storage nodes"""
    json_status = []
    hybrid_status = []
    
    for node in JSON_NODES:
        try:
            response = requests.get(f"{node}/metrics", timeout=5)
            json_status.append({"node": node, "status": "healthy", "code": response.status_code})
        except Exception as e:
            json_status.append({"node": node, "status": "unhealthy", "error": str(e)})
    
    for node in HYBRID_NODES:
        try:
            response = requests.get(f"{node}/metrics", timeout=5)
            hybrid_status.append({"node": node, "status": "healthy", "code": response.status_code})
        except Exception as e:
            hybrid_status.append({"node": node, "status": "unhealthy", "error": str(e)})
    
    return jsonify({
        "timestamp": datetime.now().isoformat(),
        "json_only_nodes": json_status,
        "hybrid_nodes": hybrid_status,
        "all_healthy": all(s["status"] == "healthy" for s in json_status + hybrid_status)
    })

@app.route('/health', methods=['GET'])
def health():
    return jsonify({
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
        "services": {
            "json_nodes": len(JSON_NODES),
            "hybrid_nodes": len(HYBRID_NODES)
        }
    })

@app.route('/', methods=['GET'])
def root():
    return jsonify({
        "service": "JSON vs Hybrid Storage Benchmarking Middleware",
        "endpoints": {
            "POST /api/compare": "Compare single query between JSON and Hybrid",
            "POST /api/benchmark/suite": "Run complete benchmark suite",
            "GET /api/benchmark/history": "Get historical benchmark results",
            "GET /api/storage/status": "Check storage node health",
            "GET /health": "Health check"
        },
        "storage_nodes": {
            "json_only": JSON_NODES,
            "hybrid": HYBRID_NODES
        }
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=False)