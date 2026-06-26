### Simulating Cross-Alert Resolution in VictoriaLogs

Two approaches were implemented to simulate OpenSearch-like alert resolution behavior in VictoriaLogs:

---

#### 1. API-Based Approach (Recommended)

In this approach, alert lifecycle is explicitly controlled using the Alertmanager API. Alerts are sent via `/api/v2/alerts` with carefully managed timestamps:

* `startsAt` defines when the alert begins (FIRING state)
* `endsAt` defines when the alert should resolve (RESOLVED state)

Both failure and recovery events use identical label sets, ensuring Alertmanager treats them as the same alert instance. The recovery event updates the existing alert by setting `endsAt` to the current time, forcing immediate resolution.

This method provides precise control over alert lifecycle and closely mimics event-driven state transitions as seen in OpenSearch.

To automate recovery, Alertmanager can route the recovery alert to a local webhook receiver. That receiver then POSTs the matching resolve payload back to `/api/v2/alerts` with `endsAt` set to the current UTC time.

---

#### 2. vmalert-Based Structural Workaround

Since vmalert does not allow direct manipulation of `startsAt` and `endsAt`, a structural workaround was implemented using evaluation intervals and rule timing behavior.

The resolution timing in vmalert follows:

> Resolve Time ≈ Evaluation Timestamp + (4 × Group Evaluation Interval)

Using this, two alert rules were designed:

* **NodeHeartbeatMissing**

  * Configured with a longer evaluation interval (30s)
  * Represents failure condition (heartbeat missing)
  * Results in slower resolution

* **NodeHeartbeatDetected**

  * Configured with a very short evaluation interval (1s)
  * Represents recovery condition (heartbeat detected)
  * Evaluates quickly and effectively overrides the previous alert behavior

By tuning evaluation intervals asymmetrically, the system simulates a priority-based resolution mechanism where the recovery signal propagates faster than the failure signal decays.

---

#### Key Insight

While the API-based approach provides direct and accurate control over alert lifecycle, the vmalert-based method demonstrates how alert resolution behavior can be indirectly influenced through timing and evaluation strategies.

This highlights a fundamental difference:

* API-based alerts → **explicit lifecycle control**
* vmalert alerts → **implicit lifecycle derived from query evaluation**

---

#### Conclusion

The combination of both approaches successfully bridges the gap between OpenSearch’s event-driven alerting model and VictoriaLogs’ time-series-based alerting system, enabling simulation of cross-alert resolution and self-healing alert pipelines.
