# Logstash — Log Transformer

Consumes logs from Kafka, transforms fields, and forwards to VictoriaLogs.

## Install
```bash
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | \
  sudo gpg --dearmor -o /usr/share/keyrings/elastic-keyring.gpg
echo 'deb [signed-by=/usr/share/keyrings/elastic-keyring.gpg] \
https://artifacts.elastic.co/packages/8.x/apt stable main' | \
  sudo tee /etc/apt/sources.list.d/elastic-9.x.list
sudo apt update && sudo apt install -y logstash
```

## Config
```bash
sudo cp hpc-pipeline.conf /etc/logstash/conf.d/
```

## Run
```bash
sudo /usr/share/logstash/bin/logstash -f /etc/logstash/conf.d/hpc-pipeline.conf
```
