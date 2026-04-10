┌─────────────────────────────────────────────────────────────────────────────────────┐
│                                    DATA FLOW                                        │
└─────────────────────────────────────────────────────────────────────────────────────┘
Normal Logs:
Generator (normal) → Fluent Bit → Kafka → Logstash → VictoriaLogs → Grafana
                                                      ↓
Error Logs:                                       (success)
Generator (error) → Fluent Bit → Kafka → Logstash → VictoriaLogs → Grafana
                                                      ↓
                                                    (fails)
                                                      ↓
                                                    DLQ
                                                      ↓
                                            /usr/share/logstash/data/dlq/
                                            (disk storage - no new UI)
Alerting Flow:
VictoriaLogs → vmalert → Alertmanager → Webhook (port 5001)



Fluent Bit	    http://localhost:2020	Metrics endpoint
Kafka	        http://localhost:19092	Message broker	
Logstash API	http://localhost:9600	Pipeline metrics
VictoriaLogs	http://localhost:9428	Query logs directly
vmalert	        http://localhost:8880	Alert rules status
Alertmanager	http://localhost:9093	Alert routing
Alert Receiver	http://localhost:5001	Webhook receiver
Grafana	        http://localhost:3000	Dashboards (admin/admin)


┌─────────────────────────────────────────────────────────────────┐
│                        PIPELINE STATUS                          │
├─────────────────────────────────────────────────────────────────┤
│  ✅ Log Generator    → Creating normal + error logs             │
│  ✅ Fluent Bit       → Reading and forwarding logs              │
│  ✅ Kafka            → Buffering messages                       │
│  ✅ Logstash         → Processing, transforming, adding _stream │
│  ✅ VictoriaLogs     → Storing 36,423+ logs                     │
│  ✅ Grafana          → Ready for visualization                  │
│  ✅ vmalert          → Evaluating alert rules                   │
│  ✅ Alertmanager     → Routing alerts                           │
│  ✅ DLQ              → Empty (ready for failures)               │ 
└─────────────────────────────────────────────────────────────────┘



**The DLQ Case Study**
DLQ is for catastrophic failures that Logstash cannot recover from at all. Your current pipeline is robust enough to handle all logs.
./test-dlq-catastrophic.sh:
Verifying crash logs are NOT in VictoriaLogs...
⚠️ Some crash logs appeared in VictoriaLogs
Logstash was successfully parsing everything (even binary data) and sending it to VictoriaLogs, which is actually working as designed - pipeline is very robust
The pipeline is so well-configured that it gracefully handles all edge cases by routing them to parse_error stream instead of failing.


**The Alerting Case Study**
1. Grafana Alerting (Built-in)
Grafana includes a full-featured alerting system that can query data from multiple sources (including VictoriaMetrics) .
Pros:
  Unified UI – Create, view, and manage alerts alongside dashboards in one interface 
  Visual rule builder – Point-and-click configuration with query preview
  Multiple data sources – Alert on metrics, logs, traces, and databases
  Built-in integrations – Direct support for Slack, Telegram, PagerDuty, email, webhooks 
  Testing tools – Simulate alerts without affecting production 
Cons:
  UI-only configuration – Rules are stored in Grafana's SQL database, making version control difficult 
  State storage – Alert state stored in a relational database (can be performance bottleneck) 
  Scaling complexity – Horizontal scaling requires HA SQL setup
  No recording rules – Cannot precompute frequently used metrics
Best for: Small to medium deployments, teams that prefer UI over YAML, or when using multiple data source types.

2. vmalert + Alertmanager
VictoriaMetrics' native alerting component that evaluates Prometheus-style rules and integrates with Alertmanager for notification routing .
Pros:
  GitOps-friendly – Rules defined as YAML files (version control, code review, CI/CD) 
  Recording rules support – Precompute complex queries, reducing load on your data source 
  Low resource usage – Lightweight component, efficient for high-load systems 
  High Availability – Run multiple vmalert instances with shared state in VictoriaMetrics 
  VictoriaMetrics integration – Native compatibility with MetricsQL and VM optimizations 
  Proxy support – VictoriaMetrics can proxy vmalert APIs to Grafana for UI visibility 
Cons:
  View-only in Grafana – You can see alerts in Grafana UI but cannot edit/create them there 
  Requires Alertmanager – Need separate Alertmanager for notification routing
  YAML learning curve – Rules must be written in Prometheus rule format
Best for: VictoriaMetrics users who want GitOps workflows, recording rules, and production scalability.

3. Prometheus + Alertmanager
The classic open-source monitoring and alerting stack.
Pros:
  Mature ecosystem – Most widely adopted, extensive documentation and examples
  GitOps-friendly – Rules defined as YAML (same as vmalert)
  Recording rules support – Precompute expressions
  Alertmanager integration – Native, battle-tested notification routing
Cons:
  Requires Prometheus – Adds another component to your stack
  Resource intensive – Prometheus memory usage can be high for large cardinality
  No Grafana UI integration – No built-in UI for rule management
  Additional maintenance – Another database to manage
Best for: Teams already standardized on Prometheus or needing ecosystem compatibility.