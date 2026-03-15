# Apache Kafka — Message Queue

Kafka acts as a durable buffer between log producers (Simulator,
Fluent Bit) and log consumers (Logstash). Running in KRaft mode
— no ZooKeeper required.

## Role in Pipeline
```
Simulator ──┐
            ├──► Kafka (hpc-logs topic) ──► Logstash
Fluent Bit ─┘
```

## Why Kafka?

- If Logstash goes down, messages wait in Kafka (24h retention)
- 6 partitions allow 6 parallel consumers for scalability
- Decouples producers from consumers completely
- Consumer group tracks exactly which messages have been processed

## KRaft Mode (No ZooKeeper)

Old Kafka required ZooKeeper as a separate service for cluster
coordination. KRaft mode (stable since Kafka 3.3) builds this
directly into Kafka — one less service to manage.

## Installation
```bash
# Download (always use archive.apache.org for specific versions)
wget https://archive.apache.org/dist/kafka/3.9.2/kafka_2.13-3.9.2.tgz
sudo tar -xzf kafka_2.13-3.9.2.tgz -C /opt/
sudo mv /opt/kafka_2.13-3.9.2 /opt/kafka

# Create system user
sudo useradd -r -s /bin/false kafka
sudo mkdir -p /var/lib/kafka/data
sudo chown -R kafka:kafka /opt/kafka /var/lib/kafka

# Format KRaft storage (one time only)
CLUSTER_ID=$(/opt/kafka/bin/kafka-storage.sh random-uuid)
/opt/kafka/bin/kafka-storage.sh format \
  -t $CLUSTER_ID \
  -c /opt/kafka/config/kraft/server.properties

# Deploy service file
sudo cp kafka.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable kafka
sudo systemctl start kafka
```

## Create Topics
```bash
# Main log topic — 6 partitions for parallel processing
/opt/kafka/bin/kafka-topics.sh --create \
  --bootstrap-server localhost:9092 \
  --topic hpc-logs \
  --partitions 6 \
  --replication-factor 1

# System events topic
/opt/kafka/bin/kafka-topics.sh --create \
  --bootstrap-server localhost:9092 \
  --topic hpc-system-events \
  --partitions 3 \
  --replication-factor 1
```

## Key Configuration Settings

| Setting | Value | Why |
|---------|-------|-----|
| process.roles | broker,controller | KRaft mode — no ZooKeeper |
| num.partitions | 6 | Max 6 parallel consumers |
| log.retention.hours | 24 | Keep messages for 24 hours |
| KAFKA_HEAP_OPTS | -Xmx512m | Limit JVM memory on dev VM |

## Verify and Monitor
```bash
# List topics
/opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --list

# View live messages
/opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic hpc-logs --max-messages 5 2>/dev/null

# Check consumer lag (0 = healthy, high = scaling problem)
/opt/kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --describe --group logstash-vlogs-consumer
```

## Data Location
```
/var/lib/kafka/data/
├── hpc-logs-0/    ← partition 0 messages
├── hpc-logs-1/    ← partition 1 messages
...
└── hpc-logs-5/    ← partition 5 messages
```
