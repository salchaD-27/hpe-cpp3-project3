# Kafka + Fluent Bit Integration Guide (Docker & Host)

## Overview

This guide shows how to integrate **Fluent Bit** with **Apache Kafka** to consume logs from Docker or host sources and output them into Kafka, including troubleshooting IPv4/IPv6 issues.

**Pipeline Flow:**

```
Docker Logs / Host Logs
        ↓
Fluent Bit
        ↓
Kafka Broker
        ↓
Kafka Console Consumer
```

---

## 1. Prerequisites

* **Kafka** installed (host or container)
* **Fluent Bit** installed (container or host)
* **Docker** (optional, if reading Docker logs)
* Basic knowledge of Docker networking

---

## 2. Kafka Broker Setup

### 2.1 Verify Kafka Port

Check if Kafka is listening:

```bash
netstat -tulpn | grep 9092
```

Example problematic output:

```
tcp6       0      0 :::9092                 :::*                    LISTEN      26325/java
```

* This means Kafka is listening on **IPv6 only**
* Clients connecting via IPv4 may get `Connection refused`.

---

### 2.2 IPv4 Fix Options

#### Option A: JVM IPv4 Stack

Add to `kafka/bin/kafka-run-class.sh`:

```bash
KAFKA_OPTS="-Djava.net.preferIPv4Stack=true"
```

Then restart Kafka.

#### Option B: Explicit IPv4 Listener (Recommended)

Edit `config/server.properties`:

```properties
listeners=PLAINTEXT://0.0.0.0:9092
advertised.listeners=PLAINTEXT://127.0.0.1:9092
listener.security.protocol.map=PLAINTEXT:PLAINTEXT
inter.broker.listener.name=PLAINTEXT
```

Restart Kafka, then verify:

```bash
netstat -tulpn | grep 9092
```

Expected output:

```
tcp 0 0 0.0.0.0:9092 0.0.0.0:* LISTEN 47238/java
```

---

### 2.3 Test Kafka Connectivity

```bash
kafka-broker-api-versions.sh --bootstrap-server 127.0.0.1:9092
```

* Should return broker metadata
* Confirms Kafka is reachable via IPv4

---

## 3. Docker Networking Considerations

* **Inside a Docker container:** `localhost` points to the container, not the host.
* Attempting `localhost:9092` from Fluent Bit inside a container → `Connection refused`.
* Solutions:

  1. Use `--network host` for Fluent Bit container → shares host network
  2. Use `host.docker.internal:9092` inside container (add `--add-host=host.docker.internal:host-gateway`)
  3. Run Kafka in Docker → use service DNS (`kafka:9092`)

---

## 4. Fluent Bit Configuration

### 4.1 Minimal Kafka Output Example

```ini
[SERVICE]
    Flush        1
    Log_Level    info

[INPUT]
    Name   tail
    Path   /logs/hpc_logs.json
    Tag    docker.logs
    Storage.Type memory

[OUTPUT]
    Name        kafka
    Match       *
    Brokers     localhost:9092
    Topics      logs
    Timestamp_Key  @timestamp
```

---

### 4.2 Run Fluent Bit with Host Network

```bash
docker run -it \
--network host \
-v "$(pwd)/fluent_bit/conf.yaml:/fluent-bit/etc/fluent-bit.yaml" \
-v "$(pwd)/fluent_bit/parsers.conf:/fluent-bit/etc/parsers.conf" \
-v "$(pwd)/logs:/logs" \
cr.fluentbit.io/fluent/fluent-bit \
--config=/fluent-bit/etc/fluent-bit.yaml
```

* Ensures `localhost:9092` resolves to host Kafka broker
* Eliminates Docker networking issues
* Use this command from the project root

---

## 5. Kafka Topic Setup

```bash
kafka-topics --create \
  --topic logs \
  --bootstrap-server 127.0.0.1:9092 \
  --partitions 1 \
  --replication-factor 1
```

---

## 6. Consume Kafka Messages

```bash
kafka-console-consumer.sh \
  --bootstrap-server 127.0.0.1:9092 \
  --topic logs \
  --from-beginning
```

Expected output:

```json
{"message":"hello from Fluent Bit"}
```

---

## 7. Troubleshooting

### 7.1 IPv4 vs IPv6 Issues

* `netstat -tulpn | grep 9092` shows `tcp6 :::9092` → Kafka IPv6 only
* Client cannot connect → `Connect to ipv4#127.0.0.1:9092 failed`
* Fix by either:

  * JVM option: `-Djava.net.preferIPv4Stack=true`
  * Kafka `listeners=PLAINTEXT://0.0.0.0:9092`

---

### 7.2 Docker Container Cannot Reach Host

Error:

```
[output:kafka:kafka.0] brokers='localhost:9092'
Connect to ipv4#127.0.0.1:9092 failed
```

* Cause: container `localhost` ≠ host `localhost`
* Fix:

  1. `--network host`
  2. `--add-host=host.docker.internal:host-gateway` and use `host.docker.internal:9092`
  3. Run Kafka in container and use container DNS

---

### 7.3 Common Commands

Check Kafka listening port:

```bash
netstat -tulpn | grep 9092
```

Test port connectivity:

```bash
nc -vz 127.0.0.1 9092
```

---

## 8. Final Notes

* Host network for Fluent Bit is simplest for local testing
* For production:

  * Use Docker Compose with Kafka + Fluent Bit in the same network
  * Configure explicit `listeners` and `advertised.listeners`
* Always check IPv4/IPv6 binding before debugging Kafka client errors

---