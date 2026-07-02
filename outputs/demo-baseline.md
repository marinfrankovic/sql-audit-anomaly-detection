# Behavioural Baseline (preloaded)

90 days of synthetic history seeded into SqlAuditPoC_CL and unioned by UnifiedSqlAudit:
- Days 1-85: normal in-role behaviour (baseline).
- Days 86-90: gradual deviations (rising anomaly scores).
- Current day: major anomalies (break-glass, DBA after-hours, DELETE, escalation, volume spike).

Baselines and trends are derived directly from this history with make-series /
series_decompose_anomalies (see kql/anomaly-detections-kql-ml.kql). No waiting required.
