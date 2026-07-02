# Detection Catalog

Detections across the three layers. Full KQL: `kql/deterministic-detections.kql` (L1),
`kql/anomaly-detections-kql-ml.kql` (L2), `kql/demo-detections.kql` (demo framing). Alerting
versions: `kql/alert-rules.kql` / `infra/modules/alerts.bicep`. Every detection produces
`EventTime, UserName, DatabaseName, ObjectName, Statement, DetectionName, RiskCategory,
AnomalyScore, Reason, RecommendedAction`.

## Layer 1 — Deterministic

| Detection | Business risk | Source | Trigger | Severity | Alert |
|-----------|---------------|--------|---------|----------|-------|
| High-risk statement | Destructive/privilege change | SQLSecurityAuditEvents | Scenario 3 | High | High-Risk SQL Statement |
| Sensitive access by non-privileged user | Data exposure | SQLSecurityAuditEvents | Scenario 2 | High | Sensitive Table Access by Non-Privileged User |
| Failed login burst | Credential attack | SQLSecurityAuditEvents | (auth failures) | Medium | Failed Login Burst |
| Break-glass used | Emergency-account misuse | SQLSecurityAuditEvents | Scenario 5 | Critical | Break-glass Account Used |
| Permission escalation | Unauthorised grant | SQLSecurityAuditEvents | Scenario 4 | High | Permission Escalation |
| Schema tampering | Structural change | SQLSecurityAuditEvents | (DDL) | High | High-Risk SQL Statement |

## Layer 2 — KQL-ML anomaly

| # | Detection | Business risk | Method | Trigger | Severity |
|---|-----------|---------------|--------|---------|----------|
| A | Query volume anomaly | Exfiltration | `make-series` + `series_decompose_anomalies` per user | Scenario 6 | Medium |
| B | Sensitive object access anomaly | Targeted access | Baseline join (first/rare) | (new sensitive) | Medium |
| C | After-hours behavioural anomaly | Unusual timing | Expected-hours datatable | Scenario 1 | Medium |
| D | Out-of-role access | Segregation of duties | Role-scope datatable | Scenario 7 | Medium |
| E | Privileged unusual object access | Insider risk | Per-user baseline | Scenario 1 | High |
| F | High-velocity enumeration | Discovery/exfil | `dcount` objects/window | Scenario 6 | Medium |
| G | High-risk statement anomaly | Destructive/DCL | Pattern | Scenario 3/4 | High |
| H | Break-glass usage | Emergency misuse | Principal match | Scenario 5 | Critical |
| I | VIP record access spike | VIP targeting | Count VIP field access | Scenario 1 | Medium |
| J | Cross-domain access | SoD breach | Forbidden-pattern datatable | Scenario 7/8 | Medium |

## Layer 3 — AI explanation (optional)

Not a detector — explains L1/L2 output. See [ai-behavior-analytics-design.md](ai-behavior-analytics-design.md).

## Field reference

- **Privileged principals:** `dba_user`, `privileged_admin`, `breakglass_admin`.
- **Sensitive objects:** `SensitiveCustomerData`, `WireTransfers`, `CustomerRiskScores`,
  `SanctionsScreening`, `FraudSignals`, `EmployeeAccessProfiles`, `AccessRequests` (catalogued in
  `auditdemo.SensitiveObjectCatalog`).
- Adjust both sets in `kql/normalization.kql` (`PrivilegedUsers` / `SensitiveObjects` / `RoleScope`).

## False-positive & production tuning

- **After-hours (C):** align expected hours to real rosters/timezones; whitelist batch/service accounts.
- **Volume (A/F):** tune `series_decompose_anomalies` sensitivity and thresholds per role; exclude
  application service accounts with legitimately high volume.
- **Out-of-role (D/J):** maintain the role→schema map from HR/IAM, not a static datatable.
- **Privileged (E):** expect noise from genuine DBA work; combine with timing/sensitivity to score.
- **First-time (B):** longer baseline windows reduce onboarding-driven false positives.

## Demo talk track

Each detection's one-liner ("what to say") is embedded in `kql/demo-detections.kql`; the full 30-min
track is in [demo-walkthrough-30min.md](demo-walkthrough-30min.md) / [demo-speaker-notes.md](demo-speaker-notes.md).
