<div align="center">
  
   # VictoriaLogs — Health & Performance
   
</div>

- A Grafana dashboard for monitoring the health, performance, and resource usage of a multi-node VictoriaLogs cluster.
- Tracks uptime, ingestion rates, memory, disk, latency, and CPU across all components in real time.

---

### 1. Cluster Overview — Uptime, Ingestion & Memory

![Overview](https://i.postimg.cc/6qJ8gQxG/1.jpg)

---

### 2. Ingestion and Data quality

![Overview](https://i.postimg.cc/9Xd0zCj9/2.jpg)


---

### 3. Storage Health

![Storage](https://i.postimg.cc/8PwCB4cp/3.jpg)

---

### 4. Resource Usage

![Overview](https://i.postimg.cc/pLTL0j50/4.jpg)

---

# Steps to add VictoriaMetrics + Cluster Health Dashboard

- Adds a metrics path (VictoriaMetrics scraping vlinsert/vlstorage/vlselect/vmauth/vlagent/vmalert/alertmanager) and a Grafana dashboard on top of it. 
- Purely additive — nothing existing is modified beyond the diffs below.

## 1. New file: `node-1-pipeline/6-victoriametrics/scrape.yml`

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

  - job_name: vlinsert
    static_configs:
      - targets: ["node-2-vlinsert-1:9428"]
        labels: {instance: "vlinsert-1"}
      - targets: ["node-3-vlinsert-2:9428"]
        labels: {instance: "vlinsert-2"}
      - targets: ["node-4-vlinsert-3:9428"]
        labels: {instance: "vlinsert-3"}

  - job_name: vlstorage-1
    static_configs:
      - targets: ["node-5-vlstorage-1:9428"]

  - job_name: vlstorage-2
    static_configs:
      - targets: ["node-6-vlstorage-2:9428"]

  - job_name: vlstorage-3
    static_configs:
      - targets: ["node-7-vlstorage-3:9428"]

  - job_name: vlselect
    static_configs:
      - targets: ["node-8-vlselect:9428"]

  - job_name: vmauth
    static_configs:
      - targets: ["node-9-vmauth:8427"]

  - job_name: vlagent
    static_configs:
      - targets: ["node-10-vlagent:9429"]
```
Match targets to actual container names/ports on nodes 2-10.

## 2. `docker-compose.yml` diff

Add service:

```yaml
  victoriametrics:
    image: victoriametrics/victoria-metrics:latest
    container_name: node-1-victoriametrics
    command:
      - "-storageDataPath=/victoria-metrics-data"
      - "-httpListenAddr=:8428"
      - "-retentionPeriod=30d"
      - "-promscrape.config=/etc/vm/scrape.yml"
      - "-promscrape.config.strictParse=false"
    volumes:
      - victoriametrics-data:/victoria-metrics-data
      - ./6-victoriametrics/scrape.yml:/etc/vm/scrape.yml:ro
    ports:
      - "8428:8428"
    restart: unless-stopped
    networks:
      - multi-node-net
```

In `vmalert.command`, append:

```yaml
      - "-remoteWrite.url=http://node-1-victoriametrics:8428/api/v1/write"
      - "-remoteRead.url=http://node-1-victoriametrics:8428"
```

In `vmalert.depends_on`, add `victoriametrics`.

In top-level `volumes:`, add `victoriametrics-data:`.

## 3. `4-grafana/provisioning/datasources/datasources.yml` diff

Add:

```yaml
  - name: VictoriaMetrics
    type: prometheus
    uid: victoriametrics
    access: proxy
    url: http://node-1-victoriametrics:8428
    isDefault: false
    editable: true
```

`uid: victoriametrics` is required as-is — the dashboard JSON references it directly.

## 4. Deploy

```bash
docker compose up -d victoriametrics
docker compose up -d vmalert
docker compose restart grafana
```
