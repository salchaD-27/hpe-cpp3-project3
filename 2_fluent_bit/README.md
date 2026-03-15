# Fluent Bit — Log Collector

Fluent Bit watches the simulator log file using inotify and forwards
each log line to Apache Kafka in real time.

## Role in Pipeline
```
/var/log/hpc-simulator/hpc-cluster.log
              ↓
         Fluent Bit
         (tail + inotify)
              ↓
         Kafka topic: hpc-logs
```

## How inotify Works

inotify is a Linux kernel mechanism that notifies Fluent Bit
instantly when new bytes are written to the log file.
No polling — zero latency log forwarding.

## Installation
```bash
# Official install script
curl https://raw.githubusercontent.com/fluent/fluent-bit/master/install.sh | sh

# Add to PATH (binary installs to non-standard location)
echo 'export PATH=$PATH:/opt/fluent-bit/bin' >> ~/.bashrc
source ~/.bashrc

# Verify
fluent-bit --version
```

## Configuration File Explained
```ini
[SERVICE]
    Flush            5        # Send to Kafka every 5 seconds
    Log_Level        info     # Log verbosity
    HTTP_Server      On       # Health check endpoint
    HTTP_Port        2020     # Health: curl localhost:2020/api/v1/health

[INPUT]
    Name             tail              # Watch a file like tail -f
    Path             /var/log/hpc-simulator/*.log
    Tag              hpc.logs          # Label for routing
    Refresh_Interval 5                 # Check for new files every 5s
    Mem_Buf_Limit    10MB              # Max memory buffer
    Parser           json              # Parse each line as JSON
    Skip_Long_Lines  On               # Skip lines over buffer limit

[OUTPUT]
    Name             kafka             # Send to Kafka
    Match            hpc.*            # Match our hpc.logs tag
    Brokers          localhost:9092   # Kafka address
    Topics           hpc-logs         # Target topic
    rdkafka.socket.keepalive.enable true
```

## Start Service
```bash
sudo systemctl enable fluent-bit
sudo systemctl start fluent-bit
sudo systemctl status fluent-bit --no-pager
```

## Verify It Is Working
```bash
# Check for errors
sudo journalctl -u fluent-bit --no-pager -n 20

# Health check
curl -s http://localhost:2020/api/v1/health

# Key log lines to look for (means it is working):
# inotify_fs_add(): name=/var/log/hpc-simulator/hpc-cluster.log
# brokers='localhost:9092' topics='hpc-logs'
```

## Common Issue — Parser Required

Without `Parser json` in the INPUT block, Fluent Bit wraps each
log line as a raw string:
```json
{"date": 1741234567, "log": "{\"_msg\": \"Job failed\", ...}"}
```

With `Parser json`, it correctly forwards the structured fields:
```json
{"_msg": "Job failed", "_time": "2026-03-15T...", "node": "..."}
```
