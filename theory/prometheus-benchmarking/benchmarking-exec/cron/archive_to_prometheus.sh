#!/usr/bin/env python3
"""
Advanced log archiver: Converts JSON logs to Prometheus metrics
and stores in cold storage tier. Runs daily via cron.
"""

import json
import os
import gzip
import requests
import argparse
from datetime import datetime, timedelta
from pathlib import Path
import sys

class LogArchiver:
    def __init__(self, warm_dir="/var/lib/victoriametrics-warm", 
                 cold_dir="/var/lib/prometheus-cold",
                 prometheus_url="http://node-3-pushgateway:9091/metrics/job/archive"):
        self.warm_dir = Path(warm_dir)
        self.cold_dir = Path(cold_dir)
        self.prometheus_url = prometheus_url
        
    def archive_old_logs(self, days_threshold=30):
        """Archive logs older than threshold days"""
        cutoff_date = datetime.now() - timedelta(days=days_threshold)
        archived_count = 0
        metrics_count = 0
        
        # Create cold directory if not exists
        self.cold_dir.mkdir(parents=True, exist_ok=True)
        
        for log_file in self.warm_dir.glob("*.jsonl.gz"):
            # Check file age
            file_mtime = datetime.fromtimestamp(log_file.stat().st_mtime)
            if file_mtime < cutoff_date:
                metrics = self.convert_to_metrics(log_file)
                metrics_count += metrics
                
                # Move to cold storage
                dest = self.cold_dir / log_file.name
                log_file.rename(dest)
                archived_count += 1
                print(f"  Archived: {log_file.name} ({metrics} metrics)")
        
        return archived_count, metrics_count
    
    def convert_to_metrics(self, gz_file):
        """Convert gzipped JSON log file to Prometheus metrics"""
        metrics_sent = 0
        metrics = []
        
        try:
            with gzip.open(gz_file, 'rt', encoding='utf-8') as f:
                for line in f:
                    try:
                        log = json.loads(line.strip())
                        timestamp = int(datetime.now().timestamp() * 1000)
                        level = log.get('level', 'INFO')
                        service = log.get('service_name', 'unknown')
                        host = log.get('host_name', 'unknown')
                        
                        # Create metrics
                        metrics.append(f'hpc_archived_logs_total{{level="{level}",service="{service}",host="{host}"}} 1 {timestamp}')
                        metrics.append(f'hpc_archived_log_bytes{{service="{service}"}} {len(line)} {timestamp}')
                        
                        if level == 'ERROR':
                            metrics.append(f'hpc_archived_errors_total{{service="{service}"}} 1 {timestamp}')
                        
                        # Batch send to avoid too many requests
                        if len(metrics) >= 100:
                            self._send_metrics(metrics)
                            metrics_sent += len(metrics)
                            metrics = []
                            
                    except json.JSONDecodeError:
                        continue
            
            # Send remaining metrics
            if metrics:
                self._send_metrics(metrics)
                metrics_sent += len(metrics)
                
        except Exception as e:
            print(f"  Error converting {gz_file.name}: {e}")
        
        return metrics_sent
    
    def _send_metrics(self, metrics):
        """Send metrics to Prometheus Pushgateway"""
        try:
            response = requests.post(
                self.prometheus_url,
                data='\n'.join(metrics),
                timeout=10
            )
            return response.status_code == 200
        except Exception as e:
            print(f"  Error sending metrics: {e}")
            return False
    
    def get_stats(self):
        """Get storage statistics"""
        warm_count = len(list(self.warm_dir.glob("*.jsonl.gz")))
        warm_size = sum(f.stat().st_size for f in self.warm_dir.glob("*.jsonl.gz")) / (1024 * 1024)
        cold_count = len(list(self.cold_dir.glob("*.jsonl.gz")))
        cold_size = sum(f.stat().st_size for f in self.cold_dir.glob("*.jsonl.gz")) / (1024 * 1024)
        
        return {
            "warm": {"files": warm_count, "size_mb": round(warm_size, 2)},
            "cold": {"files": cold_count, "size_mb": round(cold_size, 2)}
        }
    
    def run(self, days_threshold=30):
        print(f"[{datetime.now()}] Starting log archival (threshold: {days_threshold} days)")
        stats_before = self.get_stats()
        
        archived, metrics = self.archive_old_logs(days_threshold)
        
        stats_after = self.get_stats()
        
        print(f"[{datetime.now()}] Archival complete")
        print(f"  Archived: {archived} files, {metrics} metrics")
        print(f"  Warm storage: {stats_after['warm']['files']} files ({stats_after['warm']['size_mb']} MB)")
        print(f"  Cold storage: {stats_after['cold']['files']} files ({stats_after['cold']['size_mb']} MB)")
        print(f"  Space saved: {stats_before['warm']['size_mb'] - stats_after['warm']['size_mb']:.2f} MB")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Archive old logs to Prometheus')
    parser.add_argument('--days', type=int, default=30, help='Days threshold for archiving')
    parser.add_argument('--warm-dir', default='/var/lib/victoriametrics-warm', help='Warm storage directory')
    parser.add_argument('--cold-dir', default='/var/lib/prometheus-cold', help='Cold storage directory')
    
    args = parser.parse_args()
    
    archiver = LogArchiver(
        warm_dir=args.warm_dir,
        cold_dir=args.cold_dir
    )
    archiver.run(days_threshold=args.days)