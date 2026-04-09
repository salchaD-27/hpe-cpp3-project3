# Grafana — Dashboard

Visualizes logs stored in VictoriaLogs.

## Install
```bash
sudo mkdir -p /etc/apt/keyrings
wget -q -O - https://apt.grafana.com/gpg.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/grafana.gpg
echo 'deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main' | \
  sudo tee /etc/apt/sources.list.d/grafana.list
sudo apt update && sudo apt install -y grafana
sudo systemctl enable --now grafana-server
```

## Access
Open http://localhost:3000 — login: admin / admin

## Add datasource
Connections → Add new connection → search VictoriaLogs → URL: http://localhost:9428 → Save & test
