# 🚀 HPCM Observability Pipeline using Docker Compose

This project implements a **fully containerized log and event management pipeline** using:

* Kafka (streaming)
* Fluent Bit (log ingestion)
* Logstash (processing)
* VictoriaLogs (storage & querying)
* Grafana (visualization)

The system is designed to evaluate **high-performance log ingestion, processing, and observability**.

---

# 🏗️ Architecture Overview

```
Log Generator → Fluent Bit → Kafka → Logstash → VictoriaLogs → Grafana
```

---

# 📦 Docker Compose Setup

## Services Overview

| Service      | Purpose                     |
| ------------ | --------------------------- |
| Generator    | Simulates HPC logs          |
| Fluent Bit   | Collects & forwards logs    |
| Kafka        | Message broker              |
| Logstash     | Processes & transforms logs |
| VictoriaLogs | Log storage & query engine  |
| Grafana      | Visualization dashboard     |

---

## ▶️ Running Services

### 🔹 Start all services

```bash
docker compose up -d
```

### 🔹 Start individual services (debug mode)

```bash
docker compose up kafka
docker compose up fluentbit
docker compose up logstash
docker compose up victorialogs
docker compose up grafana
docker compose up generator
```

---

## 🛑 Stopping Services

```bash
docker compose down
```

### 🔹 Clean reset (remove volumes)

```bash
docker compose down -v
```

---

# 🔍 Monitoring & Debugging

---

## 🐳 1. Docker-Level Monitoring

### View logs (all services)

```bash
docker compose logs -f
```

### View specific service logs

```bash
docker logs -f kafka
docker logs -f fluentbit
docker logs -f logstash
docker logs -f victorialogs
docker logs -f grafana
```

---

## 📡 2. Kafka Monitoring

### List topics

```bash
docker exec kafka /opt/kafka/bin/kafka-topics.sh \
--list --bootstrap-server localhost:9092
```

### Consume messages

```bash
docker exec -it kafka /opt/kafka/bin/kafka-console-consumer.sh \
--topic logs --bootstrap-server localhost:9092
```

### Check message count

```bash
docker exec kafka /opt/kafka/bin/kafka-run-class.sh kafka.tools.GetOffsetShell \
--broker-list localhost:9092 --topic logs --time -1
```

### Check consumer groups

```bash
docker exec kafka /opt/kafka/bin/kafka-consumer-groups.sh \
--bootstrap-server localhost:9092 \
--describe --group logstash-group
```

---

## 📥 3. Fluent Bit Monitoring

### View logs

```bash
docker logs -f fluentbit
```

### Metrics endpoint

```bash
curl http://localhost:2020/api/v1/metrics
```

Key metrics:

* input records
* output records
* output errors

---

## 🔄 4. Logstash Monitoring

### View logs

```bash
docker logs -f logstash
```

### Check errors

```bash
docker logs logstash | grep ERROR
```

---

## 🗄️ 5. VictoriaLogs Monitoring

### Query logs

```bash
curl "http://localhost:9428/select/logsql/query?query=*&limit=10"
```

### Filter logs

#### By level

```bash
curl "http://localhost:9428/select/logsql/query?query=level:ERROR&limit=10"
```

#### By service

```bash
curl "http://localhost:9428/select/logsql/query?query=service:scheduler&limit=10"
```

### Time-based query

```bash
curl "http://localhost:9428/select/logsql/query?query=*&start=1h&limit=10"
```

### Metrics

```bash
curl http://localhost:9428/metrics
```

---

## 📊 6. Grafana Monitoring

### Access dashboard

```
http://localhost:3000
```

### Default credentials

```
admin / admin
```

### Example queries (LogsQL)

#### Count logs by level

```sql
* | stats count() by level
```

#### Logs by service

```sql
* | stats count() by service
```

#### Filter errors

```sql
level:ERROR
```

---

# 🧪 Pipeline Validation Flow

To verify the pipeline:

1. Start generator → logs created
2. Fluent Bit → forwards logs
3. Kafka → receives messages
4. Logstash → processes logs
5. VictoriaLogs → stores logs
6. Grafana → visualizes logs

---

# ⚡ Best Practices

* Use **internal Docker networking** (no ports needed except UI)
* Monitor each stage independently
* Use structured JSON logs
* Enable metrics for all services
* Validate pipeline step-by-step

---

# 🧠 Key Learnings

* Kafka acts as a **buffer and decoupling layer**
* Fluent Bit ensures **lightweight log ingestion**
* Logstash enables **data transformation**
* VictoriaLogs provides **high-performance querying**
* Grafana enables **observability and insights**

---

# 🏁 Conclusion

This setup demonstrates a **scalable, containerized observability pipeline** suitable for:

* HPC environments
* Distributed systems
* Real-time log analytics

---
