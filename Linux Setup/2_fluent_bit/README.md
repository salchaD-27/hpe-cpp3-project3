# Fluent Bit — Log Collector

Tails the simulator log file and forwards each line to Kafka.

## Install
```bash
curl https://raw.githubusercontent.com/fluent/fluent-bit/master/install.sh | sh
echo 'export PATH=/opt/fluent-bit/bin:$PATH' >> ~/.bashrc && source ~/.bashrc
```

## Config
Copy `fluent-bit.conf` and `parsers.conf` to `~/fluent-bit/`

## Run
```bash
rm -f /tmp/fluent-bit-hpc.db
fluent-bit -c ~/fluent-bit/fluent-bit.conf
```
