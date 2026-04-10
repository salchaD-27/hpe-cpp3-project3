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