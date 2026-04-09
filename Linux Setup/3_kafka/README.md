# Apache Kafka — Message Queue

Buffers log messages between Fluent Bit and Logstash. Uses KRaft mode.

## Install
```bash
mkdir -p ~/kafka && cd ~/kafka
wget https://archive.apache.org/dist/kafka/4.2.0/kafka_2.13-4.2.0.tgz
tar -xzf kafka_2.13-4.2.0.tgz
echo 'export KAFKA_HOME=~/kafka/kafka_2.13-4.2.0' >> ~/.bashrc
echo 'export PATH=$KAFKA_HOME/bin:$PATH' >> ~/.bashrc
source ~/.bashrc
```

## Config
Copy `server.properties` to `~/kafka/kafka_2.13-4.2.0/config/`

## Start
```bash
cd ~/kafka/kafka_2.13-4.2.0
KAFKA_CLUSTER_ID="$(bin/kafka-storage.sh random-uuid)"
bin/kafka-storage.sh format --standalone -t $KAFKA_CLUSTER_ID -c config/server.properties
bin/kafka-server-start.sh config/server.properties
```

## Create topic
```bash
kafka-topics.sh --create --topic hpc-logs \
  --bootstrap-server localhost:9092 \
  --partitions 3 --replication-factor 1
```
