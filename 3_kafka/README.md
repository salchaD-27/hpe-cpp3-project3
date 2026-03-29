# Apache Kafka — Message Queue

Kafka acts as a durable, high-throughput buffer between Fluent Bit (the sole log producer) and Logstash (the consumer). 
Running in **KRaft mode** — no ZooKeeper required or supported.

## Role in Pipeline
```
Fluent Bit ──► Kafka topic: hpc-logs ──► Logstash ──► VictoriaLogs
```
Kafka decouples the collection side from the processing side. If Logstash is restarted or falls behind, messages wait in Kafka for up to 24 hours without any data loss.
---
## KRaft Mode (No ZooKeeper)

All Kafka 4.x versions use **KRaft mode exclusively**. ZooKeeper support was completely removed in Kafka 4.0.0. KRaft embeds the cluster metadata
management directly into the Kafka broker process, eliminating a separate distributed system dependency and significantly reducing operational complexity.

In this single-node evaluation setup, the broker and controller roles are combined in one process — configured via `process.roles=broker,controller`.

---

## Start the Service
```bash
sudo systemctl daemon-reload
sudo systemctl enable kafka
sudo systemctl start kafka

# Check status
sudo systemctl status kafka --no-pager

# View startup logs — look for "Kafka Server started"
sudo journalctl -u kafka --no-pager -n 30
```

---

## Data Layout on Disk

After ingestion begins, the data directory reflects the partition structure:
```
/var/lib/kafka/data/
├── hpc-logs-0/          ← partition 0 segment files
├── hpc-logs-1/          ← partition 1 segment files
├── hpc-logs-2/
├── hpc-logs-3/
├── hpc-logs-4/
├── hpc-logs-5/          ← partition 5 segment files
└── __consumer_offsets-*/  ← Kafka internal offset tracking topic
```

---
