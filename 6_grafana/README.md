# Grafana — Visualization and Dashboards

Grafana connects to VictoriaLogs via the native VictoriaMetrics
logs datasource plugin and displays live HPC log dashboards.

## Role in Pipeline
```
VictoriaLogs (port 9428)
        ↓
   Grafana plugin
   (victoriametrics-logs-datasource)
        ↓
   Live dashboards (port 3000)
```

## Installation
```bash
# Add Grafana APT repository
wget -q -O - https://packages.grafana.com/gpg.key \
  | sudo gpg --dearmor \
  | sudo tee /usr/share/keyrings/grafana.gpg > /dev/null

echo "deb [signed-by=/usr/share/keyrings/grafana.gpg] \
  https://packages.grafana.com/oss/deb stable main" \
  | sudo tee /etc/apt/sources.list.d/grafana.list

sudo apt update && sudo apt install -y grafana
sudo systemctl enable grafana-server
sudo systemctl start grafana-server
```

## Plugin Installation

The VictoriaMetrics logs plugin must be installed manually
(grafana-cli is blocked by network policy on this VM):
```bash
# Download victoriametrics-logs-datasource-v0.26.2.zip
# from https://github.com/VictoriaMetrics/victorialogs-datasource/releases
# using the VM browser, then:

sudo unzip victoriametrics-logs-datasource-v0.26.2.zip \
  -d /var/lib/grafana/plugins/

# Allow unsigned plugin
sudo sed -i '/^\[plugins\]/a allow_loading_unsigned_plugins = \
  victoriametrics-logs-datasource' /etc/grafana/grafana.ini

sudo systemctl restart grafana-server
```

## Add Datasource via API
```bash
curl -s -X POST http://admin:admin@localhost:3000/api/datasources \
  -H "Content-Type: application/json" \
  -d '{
    "name":      "VictoriaLogs",
    "type":      "victoriametrics-logs-datasource",
    "url":       "http://localhost:9428",
    "access":    "proxy",
    "isDefault": true
  }'
```

## Dashboard Panels

| Panel | LogsQL Query | Purpose |
|-------|-------------|---------|
| Live Log Stream | * | All incoming logs |
| ERROR Events | level:ERROR | Error monitoring |
| SLURM Jobs | service:slurmd | Job scheduler logs |
| Critical Events | _msg:~"OOM killer" OR _msg:~"link down" | Hardware alerts |

## Access

- URL: http://localhost:3000
- Username: admin
- Password: admin

## Important Note

Do NOT use the Loki datasource type for VictoriaLogs.
VictoriaLogs does not implement the Loki API.
Always use: victoriametrics-logs-datasource plugin.
