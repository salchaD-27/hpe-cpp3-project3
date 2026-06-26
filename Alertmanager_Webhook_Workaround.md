# Cross-Alert Resolution Workaround for Alertmanager

*The alert labels effectively act as the primary key for an alert in Alertmanager.*

Alertmanager computes an alert fingerprint from the complete label set. Two alerts with different labels are treated as different alerts, while a matching label set allows Alertmanager to identify and update the existing alert.

## Overview

This document describes a proof-of-concept workaround that enables **event-driven cross-alert resolution** in a **VictoriaLogs + vmalert + Alertmanager** stack.

Unlike OpenSearch Alerting, where recovery events can explicitly resolve related alerts, Alertmanager manages each alert independently based on its fingerprint. As a result, one alert cannot directly resolve another.

To bridge this gap, a lightweight Python webhook listens for recovery alerts and uses the Alertmanager API to inject a resolve request for the corresponding active alert.

---

# Motivation

The goal of this work was to evaluate the VictoriaLogs alerting stack while exploring mechanisms to support event-driven alert lifecycle management similar to OpenSearch.

Specifically, the desired workflow is:

```
Heartbeat Missing
        │
        ▼
NodeHeartbeatMissing fires

Heartbeat Restored
        │
        ▼
NodeHeartbeatDetected fires
        │
        ▼
Automatically resolve NodeHeartbeatMissing
```

Since Alertmanager does not natively support this behavior, the webhook acts as a bridge between recovery events and the Alertmanager API.

---

# Architecture

```
Heartbeat Logs
      │
      ▼
VictoriaLogs
      │
      ▼
vmalert
      │
      ▼
Alertmanager
      │
      ├────────────► Slack
      │
      └────────────► Python Recovery Webhook
                           │
                           ▼
                  POST /api/v2/alerts
                           │
                           ▼
           Resolve NodeHeartbeatMissing
```

```
                     POST /webhook
                          │
                          ▼
                 Read Alertmanager JSON
                          │
                          ▼
     Contains RECOVERY_ALERTNAME in firing state?
                 │                    │
               No                     Yes
                │                      │
                ▼                      ▼
          Return 202           Fetch active TARGET_ALERTNAME alerts
          (Ignored)                     │
                                        ▼
                            Build resolve payload(s)
                                        │
                                        ▼
                              POST /api/v2/alerts
                                        │
                                        ▼
                             Return 200 (Resolved)
```

## Webhook Processing

The webhook acts as an event-driven bridge between Alertmanager notifications and the Alertmanager API.

For every incoming notification:

1. Receive the Alertmanager webhook payload.
2. Parse the JSON notification.
3. Check whether the payload contains the configured recovery alert (RECOVERY_ALERTNAME) in the firing state.
4. If no matching recovery alert exists, immediately return HTTP 202 (Accepted) without performing any action.
5. If a recovery alert is found:
    - Query Alertmanager for active alerts matching TARGET_ALERTNAME.
    - Construct one or more resolve payloads using the matching label sets.
    - Submit the resolve payload(s) to POST /api/v2/alerts.
6. Return HTTP 200 after successfully submitting the resolve requests.

In plain English, the webhook listens for a designated recovery alert. When that alert fires, it automatically resolves one or more related alerts by submitting resolution events to Alertmanager. Notifications that do not contain the configured recovery alert are simply acknowledged and ignored.

---

# Components

| Component      | Responsibility                                                                    |
| -------------- | --------------------------------------------------------------------------------- |
| VictoriaLogs   | Stores heartbeat logs and executes LogsQL queries                                 |
| vmalert        | Evaluates alert rules and forwards alerts to Alertmanager                         |
| Alertmanager   | Tracks alert state, deduplicates alerts, and routes notifications                 |
| Python Webhook | Listens for recovery alerts and injects resolve requests via the Alertmanager API |

---

# Alert Rules

Two independent alert rules are defined.

## NodeHeartbeatMissing

Represents a missing heartbeat condition.

* Severity: `critical`
* Evaluation interval: **20 s** (testing configuration)

## NodeHeartbeatDetected

Represents heartbeat recovery.

* Severity: `critical`
* Evaluation interval: **10 s**

The alerts intentionally use different names so that each produces a unique fingerprint and can be managed independently.

---

# Alertmanager Configuration

Recovery alerts are routed to the webhook receiver.

```yaml
route:
  routes:
    - match:
        alertname: NodeHeartbeatDetected
      receiver: heartbeat-recovery-webhook
```

Webhook receiver:

```yaml
receivers:
  - name: heartbeat-recovery-webhook
    webhook_configs:
      - url: http://alert-resolve-webhook:8080/webhook
        send_resolved: true
```

Alertmanager generates two webhook notifications for each recovery alert:

1. `firing`
2. `resolved`

The webhook processes only **firing** notifications. Resolved notifications are ignored because the resolve operation has already been performed.

---

# Webhook Workflow

For every incoming webhook request:

1. Receive the Alertmanager notification.
2. Filter alerts where:

   * `alertname == NodeHeartbeatDetected`
   * `status == firing`
3. Construct a new Alertmanager API payload.
4. Replace the alert name with `NodeHeartbeatMissing`.
5. Preserve the remaining labels exactly.
6. Set `endsAt` to the current UTC timestamp.
7. Submit the payload to:

```
POST /api/v2/alerts
```

Alertmanager matches the existing active alert using its fingerprint and immediately transitions it to the resolved state.

---

# Design Principle

*The alert labels effectively act as the primary key for an alert in Alertmanager.*

Alertmanager identifies alerts using a fingerprint derived from their complete label set. This means that modifying any label changes the alert's identity. Consequently, a resolve request must preserve the original labels so that Alertmanager can locate and update the intended active alert.

This design principle is the foundation of the webhook workaround.

---

# Fingerprint Requirement

The most important implementation detail is that the resolve payload must contain **the same label set** as the active alert.

Alertmanager identifies alerts using a fingerprint derived from their labels.

Therefore:

* identical labels → existing alert is updated/resolved
* modified labels → new fingerprint → no matching alert is found

Even seemingly harmless label changes (for example replacing `node=node-a` with `stats_result=1`) generate a different fingerprint and prevent resolution.

Only the translated alert name should differ as required by the workflow.

---

# Test Procedure

## 1. Start the stack

```bash
docker compose up -d
```

---

## 2. Monitor Alertmanager

```bash
watch -n1 'curl -s localhost:9093/api/v2/alerts | jq ".[] | {name:.labels.alertname,state:.status.state,endsAt:.endsAt}"'
```

---

## 3. Monitor webhook logs

```bash
docker logs -f alert-resolve-webhook
```

---

## 4. Monitor vmalert

```bash
docker logs -f vmalert
```

---

## 5. Trigger heartbeat failure

```bash
./no_heartbeat.sh
```

Expected result:

* `NodeHeartbeatMissing` enters the **firing** state.

---

## 6. Trigger heartbeat recovery

Stop the failure script:

```bash
Ctrl+C
```

Start heartbeat generation:

```bash
./heartbeat.sh
```

Expected sequence:

1. `NodeHeartbeatDetected` fires.
2. Alertmanager forwards the notification to the webhook.
3. The webhook submits a resolve request.
4. `NodeHeartbeatMissing` is resolved immediately.
5. `NodeHeartbeatDetected` remains active until its own rule resolves.

---

# Expected Webhook Output

```
Incoming webhook request

Matched recovery alert

Built resolve payload

Posting resolve payload

Alertmanager response status=200

Resolve flow completed successfully
```

---

# Alert Lifecycle

```
NodeHeartbeatMissing
        │
        ▼
      FIRING
        │
        │ Heartbeat restored
        ▼
NodeHeartbeatDetected fires
        │
        ▼
Webhook invoked
        │
        ▼
POST /api/v2/alerts
        │
        ▼
NodeHeartbeatMissing resolved
```

---

# Troubleshooting

If the alert is not resolved as expected:

* Verify the webhook receives a **firing** notification.
* Ignore **resolved** webhook notifications.
* Compare the labels of the active alert and the generated resolve payload.
* Confirm that the webhook posts to `/api/v2/alerts`.
* Verify Alertmanager returns **HTTP 200**.
* Inspect active alerts:

```bash
curl -s localhost:9093/api/v2/alerts | jq
```

Useful monitoring commands:

```bash
watch -n0.5 'curl -s localhost:9093/api/v2/alerts | jq'
```

```bash
watch -n1 'curl -s localhost:9093/api/v2/alerts | jq ".[] | {name:.labels.alertname,state:.status.state,endsAt:.endsAt,summary:.annotations.summary,fingerprint:.fingerprint,receiver:.receivers[0].name}"'
```

---

# Key Findings

This prototype demonstrates that Alertmanager can be used to implement event-driven alert lifecycle management with minimal additional infrastructure.

Key observations include:

* Alert fingerprints are derived exclusively from alert labels.
* Matching label sets are required for Alertmanager to update or resolve an existing alert.
* Distinct alert names allow independent alert lifecycles while enabling explicit cross-alert resolution.
* A lightweight webhook bridge can emulate OpenSearch-style recovery semantics without modifying Alertmanager or vmalert.

## Root Cause Analysis

During the development of the webhook-based workaround, several iterations were required to isolate the conditions under which Alertmanager would successfully resolve an existing alert. The primary observations are summarized below.

### 1. Cross-alert resolution is not natively supported

Unlike OpenSearch Alerting, Alertmanager does not provide a mechanism for one alert to explicitly resolve another. Each alert is managed independently based on its fingerprint, requiring an external component to bridge recovery events and alert resolution.

### 2. Alert fingerprints depend entirely on labels

Initial attempts constructed resolve payloads using fixed label sets. Although Alertmanager accepted these requests (HTTP 200), the active alerts remained unresolved because the generated label set differed from the labels of the active alert.

For example, replacing:

```
node=node-a
```

with

```
stats_result=heartbeats
```

produced a different fingerprint. Since Alertmanager derives the fingerprint from the complete label set, it treated the resolve payload as a different alert rather than an update to the existing one.

This experiment confirmed that identical labels are essential for Alertmanager to associate a resolve request with an active alert.

### 3. Preserving label consistency

After modifying the webhook to preserve the label set of the target alert, Alertmanager immediately transitioned the active alert to the resolved state once the resolve payload was submitted through the Alerts API.

This demonstrated that successful cross-alert resolution depends on maintaining label consistency between the active alert and the injected resolve request.

### 4. FIRING versus RESOLVED webhook notifications

Alertmanager generates two webhook notifications when `send_resolved: true` is enabled:

* **FIRING** – generated when the recovery alert becomes active.
* **RESOLVED** – generated when the recovery alert naturally resolves.

Only FIRING notifications are relevant to the workaround because they indicate that the recovery condition has occurred. RESOLVED notifications are expected later in the alert lifecycle and are intentionally ignored by the webhook.

### 5. Alert timing considerations

During testing, the evaluation intervals of the heartbeat rules were adjusted to ensure that the missing-heartbeat alert remained active long enough for the recovery alert to trigger the webhook.

This provided a deterministic overlap between:

* `NodeHeartbeatMissing`
* `NodeHeartbeatDetected`

allowing the webhook to submit the resolve request before the missing alert naturally expired.

### 6. Validation through controlled experiments

The workaround was validated using two complementary approaches:

1. **Manual Alertmanager API testing**

   Alerts were manually injected using the `/api/v2/alerts` endpoint to verify that externally submitted resolve payloads could transition active alerts to the resolved state.

2. **End-to-end pipeline testing**

   Heartbeat generator scripts (`heartbeat.sh` and `no_heartbeat.sh`) were executed while monitoring Alertmanager, vmalert, and the webhook logs. Successful execution consistently produced the following sequence:

```
NodeHeartbeatMissing
        │
        ▼
ACTIVE

Heartbeat restored

        │
        ▼
NodeHeartbeatDetected

        │
        ▼
Webhook invoked

        │
        ▼
POST /api/v2/alerts

        │
        ▼
NodeHeartbeatMissing resolved
```

These experiments demonstrate that the webhook successfully emulates event-driven cross-alert resolution while remaining independent of modifications to Alertmanager or vmalert.

---

# Comparison with OpenSearch Alerting

One objective of this evaluation was to compare VictoriaLogs-based alerting with the alert lifecycle management capabilities available in OpenSearch Alerting.

| Feature                           | OpenSearch Alerting | VictoriaLogs + vmalert | Implemented Workaround |
| --------------------------------- | ------------------- | ---------------------- | ---------------------- |
| Independent alert rules           | ✓                   | ✓                      | ✓                      |
| Alert routing                     | ✓                   | ✓ (Alertmanager)       | ✓                      |
| Dynamic alert notifications       | ✓                   | ✓                      | ✓                      |
| Cross-alert resolution            | ✓                   | ✗                      | ✓ (Webhook bridge)     |
| Event-driven recovery actions     | ✓                   | Limited                | ✓                      |
| Automatic alert lifecycle control | Native              | Rule-based             | Webhook-driven         |

### Native OpenSearch behaviour

OpenSearch allows recovery events to participate directly in the alert lifecycle. A recovery condition can explicitly resolve a previously fired alert without requiring an external component. This enables workflows where alert state transitions are naturally driven by events.

### Native VictoriaLogs + Alertmanager behaviour

VictoriaLogs and vmalert evaluate alert rules independently and forward the resulting alerts to Alertmanager. Alertmanager maintains alert state using fingerprints derived from alert labels.

Because alerts are managed independently, one alert cannot directly resolve another. Recovery events therefore generate separate alerts rather than modifying the lifecycle of existing alerts.

### Webhook-based extension

The implemented webhook extends this behaviour by introducing an event-driven translation layer.

Instead of modifying Alertmanager or vmalert, the webhook observes recovery alerts and converts them into Alertmanager API requests that resolve the corresponding active alerts.

The resulting workflow closely resembles the behaviour provided natively by OpenSearch:

```
Recovery Event
        │
        ▼
NodeHeartbeatDetected

        │
        ▼
Webhook

        │
        ▼
Translate recovery event

        │
        ▼
POST /api/v2/alerts

        │
        ▼
Resolve NodeHeartbeatMissing
```

### Evaluation Summary

The evaluation demonstrates that VictoriaLogs, vmalert, and Alertmanager provide a robust foundation for log-based alerting but do not natively support event-driven cross-alert resolution.

However, this limitation can be effectively addressed using a lightweight webhook service that integrates with the Alertmanager Alerts API. The solution requires no modifications to Alertmanager or vmalert, introduces minimal operational overhead, and successfully reproduces OpenSearch-style recovery semantics while preserving the existing alerting architecture.
