# Single Node HPC Log Pipeline

Pipeline: Simulator → Fluent Bit → Kafka → Logstash → VictoriaLogs → Grafana

## Architecture

| Step | Component    | Role                           | Port |
|------|--------------|--------------------------------|------|
| 1    | Simulator    | Generates structured JSON logs | —    |
| 2    | Fluent Bit   | Tails log file, sends to Kafka | —    |
| 3    | Kafka        | Message buffer and topic queue | 9092 |
| 4    | Logstash     | Transforms and routes logs     | —    |
| 5    | VictoriaLogs | Stores and indexes log data    | 9428 |
| 6    | Grafana      | Dashboard and visualization    | 3000 |

## Requirements
- Ubuntu 22.04+
- Java 17: `sudo apt install -y openjdk-17-jdk`
- Python 3: `sudo apt install -y python3 python3-pip`

## Setup
See the README inside each numbered folder for install and config steps.

## Running the pipeline
```bash
# Tab 1 - Kafka
cd ~/kafka/kafka_2.13-4.2.0 && bin/kafka-server-start.sh config/server.properties

# Tab 2 - VictoriaLogs
cd ~/victorialogs && ./victoria-logs-prod -storageDataPath=./data -httpListenAddr=:9428

# Tab 3 - Simulator
python3 1_simulator/simulator.py --rate 5

# Tab 4 - Fluent Bit
fluent-bit -c ~/fluent-bit/fluent-bit.conf

# Tab 5 - Logstash
sudo /usr/share/logstash/bin/logstash -f /etc/logstash/conf.d/hpc-pipeline.conf
```

## Verify
```bash
curl 'http://localhost:9428/select/logsql/query?query=*&limit=5'
```
