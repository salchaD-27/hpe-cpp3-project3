# Apache Kafka Single-Node Setup (KRaft Mode)

This guide walks you through setting up a **single-node Apache Kafka cluster** using **KRaft mode** (Kafka without ZooKeeper) on a Linux system. It also shows how to create a topic and verify the setup.

---

## Download and Extract Kafka

Download the Kafka binary (version 3.7.0) from the official Apache mirrors and extract it:

```bash
wget https://downloads.apache.org/kafka/3.7.0/kafka_2.13-3.7.0.tgz
tar -xzf kafka_2.13-3.7.0.tgz
cd kafka_2.13-3.7.0
```

## Kafka Version Modes

| Kafka Version       | Mode                          | Notes                                                                 |
|--------------------|-------------------------------|-----------------------------------------------------------------------|
| `< 3.6`             | ZooKeeper                     | Classic mode, requires a separate ZooKeeper instance to manage metadata. |
| `~ 3.6`             | ZooKeeper + KRaft             | Transitional versions support both ZooKeeper and early KRaft mode.       |
| `> 3.6`             | KRaft (Kafka Raft Metadata)   | Newer versions run Kafka in KRaft mode without ZooKeeper.                |

## Generate cluster id

```bash
id="$(bin/kafka-storage.sh random-uuid)"
```

## Format storage

```bash
bin/kafka-storage.sh format -t $id -c config/server.properties 
```

## Start Kafka

```bash
bin/kafka-server-start.sh config/kraft/server.properties
```

## Create topic

```bash
bin/kafka-topics.sh --create \
--topic logs \
--bootstrap-server localhost:9092
```

## Check

```bash
bin/kafka-topics.sh --list --bootstrap-server localhost:9092
```
