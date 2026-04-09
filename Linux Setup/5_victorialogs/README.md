# VictoriaLogs — Log Storage

Stores and indexes all log data. Queryable via LogsQL.

## Install
```bash
mkdir -p ~/victorialogs/data && cd ~/victorialogs
wget https://github.com/VictoriaMetrics/VictoriaMetrics/releases/latest/download/victoria-logs-linux-amd64-v1.47.0.tar.gz
tar -xzf victoria-logs-linux-amd64-v1.47.0.tar.gz
chmod +x victoria-logs-prod
```

## Run
```bash
./victoria-logs-prod -storageDataPath=./data -retentionPeriod=7d -httpListenAddr=:9428
```

## Verify
```bash
curl http://localhost:9428/health
curl 'http://localhost:9428/select/logsql/query?query=*&limit=5'
```

See `victorialogs-sample.json` for example stored log records.
