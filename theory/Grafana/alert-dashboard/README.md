# Alerting Dashboard — Approach History

## 1. Previous Approach

**Stack:** Grafana + a dedicated VictoriaMetrics instance (Prometheus-compatible) scraping
Alertmanager's native `/metrics` endpoint, queried via Grafana's built-in `prometheus` datasource
type.

> **Note:** this is the actual `docker-compose.yml` for Node 1 — it also runs the log pipeline
> (`simulator`, `fluent-bit`, `kafka`, `logstash`, `kafka-ui`) in the same file. Those services are
> identical between the previous and current alerting approaches and are **not touched** by the
> steps below — only the `victoriametrics`, `vmalert`, `alertmanager`, and `grafana` blocks (and
> their provisioning files) change between approaches, so reverting to/from this approach never
> affects the unrelated pipeline services.

### 1.1 Previous Alerting-related services

```yaml
  victoriametrics:
    image: victoriametrics/victoria-metrics:v1.115.0
    container_name: node-1-victoriametrics
    command:
      - "-storageDataPath=/storage"
      - "-retentionPeriod=3"
      - "-httpListenAddr=:8428"
      - "-promscrape.config=/etc/vm/scrape.yml"      # scrape Alertmanager
      - "-promscrape.config.strictParse=false"        # tolerate unknown fields
    volumes:
      - victoriametrics-data:/storage
      - ./6-victoriametrics/scrape.yml:/etc/vm/scrape.yml:ro
    ports:
      - "8428:8428"
    restart: unless-stopped
    networks:
      - pipeline-net
      - multi-node-net

  grafana:
    image: grafana/grafana:11.4.0
    container_name: node-1-grafana
    ports:
      - "3001:3000"
    environment:
      GF_SECURITY_ADMIN_USER: admin
      GF_SECURITY_ADMIN_PASSWORD: admin
      GF_USERS_ALLOW_SIGN_UP: "false"
      GF_INSTALL_PLUGINS: victoriametrics-logs-datasource
    volumes:
      - ./4-grafana/provisioning/datasources:/etc/grafana/provisioning/datasources:ro
      - grafana-data:/var/lib/grafana
    depends_on:
      - victoriametrics
    restart: unless-stopped
    networks:
      - pipeline-net
      - multi-node-net
    deploy:
      resources:
        limits:
          memory: 256M

  vmalert:
    image: victoriametrics/vmalert:latest
    container_name: node-1-vmalert
    ports:
      - "8881:8880"
    command:
      - "-datasource.url=http://node-5-vlselect:9428"
      - "-datasource.queryStep=30s"
      - "-notifier.url=http://node-1-alertmanager:9093"
      - "-remoteWrite.url=http://node-1-victoriametrics:8428"
      - "-remoteRead.url=http://node-1-victoriametrics:8428"
      - "-rule=/etc/alerts/*.yml"
      - "-evaluationInterval=30s"
      - "-httpListenAddr=:8880"
    volumes:
      - ./5-vmalert/alerts:/etc/alerts:ro
    depends_on:
      - alertmanager
      - victoriametrics
    restart: unless-stopped
    networks:
      - pipeline-net
      - multi-node-net

  alertmanager:
    image: prom/alertmanager:v0.31.1
    container_name: node-1-alertmanager
    ports:
      - "9095:9093"
    volumes:
      - ./5-vmalert/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro
    command:
      - "--config.file=/etc/alertmanager/alertmanager.yml"
      - "--storage.path=/alertmanager"
    restart: unless-stopped
    networks:
      - pipeline-net
    deploy:
      resources:
        limits:
          memory: 64M
```

### 1.2 Scrape config (`6-victoriametrics/scrape.yml`)

```yaml
scrape_configs:
  - job_name: alertmanager
    static_configs:
      - targets: ["node-1-alertmanager:9093"]

  - job_name: vmalert
    static_configs:
      - targets: ["node-1-vmalert:8880"]

  - job_name: victoriametrics
    static_configs:
      - targets: ["node-1-victoriametrics:8428"]
```

### 1.3 Grafana datasources (`4-grafana/provisioning/datasources/datasources.yml`)

```yaml
apiVersion: 1

datasources:
  - name: VictoriaLogs
    type: victoriametrics-logs-datasource
    access: proxy
    url: http://node-5-vlselect:9428
    isDefault: true
    editable: true

  - name: VictoriaMetrics
    type: prometheus
    access: proxy
    url: http://node-1-victoriametrics:8428
    isDefault: false
    editable: true

  - name: Alertmanager
    uid: alertmanager-native
    type: prometheus
    access: proxy
    url: http://node-1-alertmanager:9093
    isDefault: false
    editable: true
    jsonData:
      timeInterval: "30s"
```

### 1.4 Steps to reproduce this approach

These steps touch **only** the four service blocks above and their provisioning files — the
`simulator`, `fluent-bit`, `kafka`, `logstash`, and `kafka-ui` blocks in `docker-compose.yml` stay
exactly as they are and are unaffected either way.

1. In `docker-compose.yml`, add the `victoriametrics` service block from 1.1, mounting
   `8-victoriametrics/scrape.yml` at `/etc/vm/scrape.yml`.
2. Create `6-victoriametrics/scrape.yml` with the job list in 1.2.
3. Set `vmalert`'s command to the one in 1.1: `-datasource.url` pointed directly at
   `node-5-vlselect:9428`, with `-remoteWrite.url` / `-remoteRead.url` pointed at
   `node-1-victoriametrics:8428` so `ALERTS{}` state gets persisted there.
4. Replace `4-grafana/provisioning/datasources/datasources.yml` with the version in 1.3 —
   `VictoriaLogs`, plus `VictoriaMetrics` and `Alertmanager` as `prometheus`-type datasources.
5. Restart only the affected containers, leaving the rest of the pipeline running:
   ```bash
   docker compose up -d --no-deps victoriametrics vmalert alertmanager grafana
   ```
6. Build dashboard panels against the `VictoriaMetrics` and `Alertmanager` Prometheus datasources
   using PromQL (e.g. `ALERTS`, `alertmanager_alerts`, `alertmanager_notifications_total`).

### 1.5 Why this approach was used

Alertmanager natively exposes a Prometheus-format `/metrics` endpoint, so the path of least
resistance was to scrape it like any other target and reuse Grafana's built-in `prometheus`
datasource type. This avoided installing any extra Grafana plugins and kept the whole alerting
stack speaking one query language (PromQL) end-to-end — simple to stand up and consistent with how
the rest of the metrics pipeline was already built.

### 1.6 Drawbacks

- **Alertmanager's `/metrics` only exposes aggregate operational counters** — things like
  `alertmanager_alerts`, `alertmanager_notifications_total`, and request-duration histograms — not
  the actual alert objects. The real per-alert data (labels, annotations, `startsAt`/`endsAt`,
  generator URL) only exists behind Alertmanager's REST API (`/api/v2/alerts`), which a Prometheus
  datasource cannot query. This meant the old dashboard could show *counts* of firing alerts but
  not *which* alerts were firing or their labels/annotations in a readable table.
- **An extra, redundant VictoriaMetrics instance** had to be stood up purely to give Alertmanager's
  metrics a place to be scraped into, adding another moving part to maintain.

---

## 2. Current Approach

**Stack:** Grafana, with Alertmanager's actual alert data pulled via the
`yesoreyeram-infinity-datasource` plugin hitting Alertmanager's REST API directly, instead of
scraping its Prometheus `/metrics` endpoint.

### 2.1 Relevant services (`docker-compose.yml`)

```yaml
  vmalert:
    image: victoriametrics/vmalert:latest
    container_name: node-1-vmalert
    command:
      - "-datasource.url=http://node-5-vlselect:9428"
      - "-datasource.queryStep=30s"
      - "-rule=/etc/alerts/*.yml"
      - "-rule=/etc/alerts/cross-alerting/*.yml"
      - "-evaluationInterval=30s"
      - "-httpListenAddr=:8880"
      - "-notifier.url=http://node-1-alertmanager:9093"
    volumes:
      - ./5-vmalert/alerting/vmalert:/etc/alerts:ro
      - ./5-vmalert/alerting/vmalert/cross-alerting:/etc/alerts/cross-alerting:ro
    ports:
      - "8881:8880"

  grafana:
    image: grafana/grafana:11.6.15
    container_name: node-1-grafana
    environment:
      GF_INSTALL_PLUGINS: victoriametrics-logs-datasource,yesoreyeram-infinity-datasource
    volumes:
      - ./4-grafana/provisioning/datasources:/etc/grafana/provisioning/datasources:ro
      - grafana-data:/var/lib/grafana
    ports:
      - "3001:3000"

  alertmanager:
    image: prom/alertmanager:latest
    container_name: node-1-alertmanager
    volumes:
      - ./5-vmalert/alerting/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro
    command:
      - "--config.file=/etc/alertmanager/alertmanager.yml"
      - "--web.listen-address=:9093"
    ports:
      - "9095:9093"
```

### 2.2 Grafana datasources (`4-grafana/provisioning/datasources/datasources.yml`)

```yaml
apiVersion: 1

datasources:
  - name: VictoriaLogs
    type: victoriametrics-logs-datasource
    access: proxy
    url: http://node-5-vlselect:9428
    jsonData:
      maxLines: 1000
      timeInterval: "30s"
      queryTimeout: "30s"
    isDefault: true
    editable: true

  # Generic JSON datasource used to query Alertmanager's real REST API
  - name: Infinity-Alertmanager
    uid: infinity-alertmanager
    type: yesoreyeram-infinity-datasource
    access: proxy
    jsonData:
      datasource_mode: "advance"
      allowedHosts:
        - "http://node-1-alertmanager:9093"
    isDefault: false
    editable: true
```

### 2.3 What changed, concretely (diff against the previous approach)

**Remove:**
- The standalone `victoriametrics` service and its `scrape.yml` (no longer needed to expose
  Alertmanager's `/metrics`).
- The `Alertmanager` and `VictoriaMetrics` Prometheus-type Grafana datasources.
- `vmalert`'s `-remoteWrite.url` / `-remoteRead.url` flags (alert state no longer needs to be
  persisted to a separate VictoriaMetrics instance).

**Add:**
- A second rule path: `-rule=/etc/alerts/cross-alerting/*.yml` for cross-node alert rules.
- The `yesoreyeram-infinity-datasource` plugin in Grafana, with an `Infinity-Alertmanager`
  datasource configured in `advance` mode against Alertmanager's real REST API
  (`http://node-1-alertmanager:9093`).

### 2.4 Why this approach was chosen

Alertmanager's REST API (`/api/v2/alerts`, `/api/v2/silences`) returns the actual alert objects —
labels, annotations, `startsAt`/`endsAt`, generator URL — the same data `amtool` uses to print a
full alert listing. The Infinity datasource can call that API directly and return it as structured
JSON, which Grafana can render as a real table of "what's currently firing, with what labels and
annotations" rather than just a count.

### 2.5 Benefits

- **Real alert detail, not just counts.** Dashboards can now show alert name, severity, labels,
  annotations, and timing per alert — information that was structurally unavailable through
  Alertmanager's Prometheus `/metrics` endpoint.
- **One fewer moving part.** No dedicated VictoriaMetrics instance/scrape config needed just to
  expose Alertmanager's operational counters.
- **Room for cross-node alert rules** via the dedicated `cross-alerting/` rules directory.

---

## 3. Screenshots

### Previous dashboard

<!-- PASTE SCREENSHOT(S) OF THE OLD DASHBOARD HERE -->

### Current dashboard

<!-- PASTE SCREENSHOT(S) OF THE NEW DASHBOARD HERE -->