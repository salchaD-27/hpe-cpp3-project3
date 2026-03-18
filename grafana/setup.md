## 1. Install Grafana on Arch Linux

On Arch, Grafana is available in the official repositories.

```bash
sudo pacman -Syu grafana
```

This installs the Grafana server.

---

## 2. Enable and Start the Grafana Service

Run:

```bash
sudo systemctl enable grafana
sudo systemctl start grafana
```

Check if it’s running:

```bash
systemctl status grafana
```

Grafana runs on **port 3000 by default**.

---

## 3. Open the Web Interface

Open a browser and go to:

```
http://localhost:3000
```

Default login:

* **Username:** `admin`
* **Password:** `admin`

Grafana will ask you to change the password.

---

## 4. Add a Sample Data Source

For testing input/output, the easiest option is **TestData DB** (built into Grafana).

Steps:

1. Click **Connections**
2. Click **Add new connection**
3. Choose **TestData DB**
4. Click **Save & Test**

This creates a **fake dataset generator** useful for experiments.

---

## 5. Create a Sample Dashboard (Input → Output Test)

1. Click **Dashboards**
2. **New → Add Visualization**
3. Select **TestData DB**
4. Choose a scenario like:

   * `Random Walk`
   * `CSV Content`
   * `Predictable Pulse`

Example **CSV input test**

Paste sample data:

```
time,value
2026-03-13T10:00:00Z,10
2026-03-13T10:01:00Z,20
2026-03-13T10:02:00Z,15
2026-03-13T10:03:00Z,30
```

Grafana output → **time series graph**.

---

## 6. Example Query Test

In the panel query:

```
Scenario: Random Walk
Series count: 3
Points: 100
```

Output → 3 generated time-series lines.

This verifies:

* input parameters → query engine
* output → visualization rendering.

---

## 7. CLI Test (Check API)

You can also test Grafana API:

```bash
curl http://localhost:3000/api/health
```

Expected output:

```json
{
  "database": "ok",
  "version": "x.x.x"
}
```

---

## 8. Verify Grafana Logs

```bash
journalctl -u grafana -f
```

This helps confirm dashboard queries are executing.