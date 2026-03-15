# Logstash — Pipeline Processor

Logstash reads log events from Kafka, removes internal fields
that conflict with VictoriaLogs, and forwards clean JSON to
VictoriaLogs for storage.

## Role in Pipeline
```
Kafka (hpc-logs topic)
        ↓
    Logstash
    - reads with 3 consumer threads
    - removes @version, @timestamp
    - forwards clean JSON
        ↓
VictoriaLogs (/insert/jsonline)
```

## Installation
```bash
# Add Elastic APT repository
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch \
  | sudo gpg --dearmor -o /usr/share/keyrings/elastic-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/elastic-keyring.gpg] \
  https://artifacts.elastic.co/packages/8.x/apt stable main" \
  | sudo tee /etc/apt/sources.list.d/elastic-8.x.list

sudo apt update && sudo apt install -y logstash

# Fix permissions
sudo chown -R logstash:logstash /usr/share/logstash/data
sudo chown -R logstash:logstash /usr/share/logstash/logs

# Tune JVM memory (default 1GB is too high for dev VM)
sudo tee /etc/logstash/jvm.options.d/heap.options << 'JVMEOF'
-Xms256m
-Xmx512m
JVMEOF
```

## Pipeline Configuration Explained
```ruby
input {
  kafka {
    bootstrap_servers => "localhost:9092"
    topics            => ["hpc-logs"]
    group_id          => "logstash-vlogs-consumer"
    codec             => "json"
    consumer_threads  => 3    # 3 threads × 2 partitions = all 6 covered
    auto_offset_reset => "earliest"
  }
}

filter {
  # Only add _msg if simulator did not already send it
  if ![_msg] {
    mutate { add_field => { "_msg" => "%{message}" } }
  }
  # CRITICAL: Remove Logstash internal fields
  # @timestamp conflicts with simulator _time field
  # If both exist, _time becomes an array → VictoriaLogs rejects with 400
  mutate {
    remove_field => ["@version", "@timestamp", "event", "message"]
  }
}

output {
  http {
    url          => "http://localhost:9428/insert/jsonline"
    http_method  => "post"
    content_type => "application/stream+json"
    format       => "json"
  }
}
```

## Critical Bug Fixed — Duplicate _time Field

VictoriaLogs was returning HTTP 400 errors because Logstash was
adding its own @timestamp which merged with the simulator _time
field to create an array:
```
_time: ["2026-03-15T06:13:03Z", "2026-03-15T06:13:03.939Z"]
```

VictoriaLogs cannot parse an array as a timestamp. Fix: always
remove @timestamp in the filter block.

## Deploy and Start
```bash
sudo cp hpc-pipeline.conf /etc/logstash/conf.d/
sudo systemctl enable logstash
sudo systemctl start logstash

# Monitor pipeline
sudo journalctl -fu logstash --no-pager
```
