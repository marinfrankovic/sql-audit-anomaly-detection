# 30-Minute Contoso Bank Customer Demo Playbook

> **Opening message**
> "Today we are proving that Contoso Bank can see **who** accessed **what database records**, **when**,
> **from where**, and whether the behaviour looks **normal or abnormal** — even when the user has
> legitimate elevated access."

**Demo-ready immediately after deployment.** 90 days of history, baselines, anomaly scores, trend
data and AI examples are preloaded. You do **not** generate baseline data in front of the customer.
Optionally run the WOW scenarios live to add fresh events. Speaker notes with fallbacks:
[demo-speaker-notes.md](demo-speaker-notes.md).

## Agenda

| Time | Section |
|------|---------|
| 0:00-02:00 | Opening / framing |
| 02:00-05:00 | Architecture |
| 05:00-08:00 | Raw audit evidence |
| 08:00-12:00 | Workbook executive view |
| 12:00-17:00 | Run WOW scenarios |
| 17:00-21:00 | Anomaly detections |
| 21:00-25:00 | AI-assisted investigation |
| 25:00-28:00 | Alerting & SOC handoff |
| 28:00-30:00 | Close / production discussion |

---

## 0:00-02:00 — Opening / framing
> "Contoso Bank does not only need to know that logs exist. The real question is whether we can understand
> if database access behaviour is normal or abnormal, especially for privileged users."

## 02:00-05:00 — Architecture
Show [architecture.md](architecture.md) / `architecture.drawio`: Azure SQL, SQL Server on Azure VM,
Log Analytics, Workbook, Alerts, optional Sentinel/UEBA, optional AI Analyst.
> "We start with deterministic audit trails, then add behavioural baselines, then AI-assisted
> explanation. Three layers — defence in depth."

## 05:00-08:00 — Raw audit evidence
Log Analytics → Logs:
```kusto
UnifiedSqlAudit
| where EventTime > ago(1h)
| project EventTime, SourceType, UserName, DatabaseName, ObjectName, Action, Statement
| order by EventTime desc
```
Also show that 90 days already exist:
```kusto
SqlAuditPoC_CL | summarize count() by bin(TimeGenerated, 1d) | render columnchart
```
> "Notice we already have 90 days of behaviour — baselines exist today, no waiting for ML to learn."

## 08:00-12:00 — Workbook executive view
Open **Contoso Bank SQL Audit & AI Behavior Analytics PoC**, TimeRange = **30 days**. Walk §1 Executive
Overview (tiles), §2 timeline + **query volume baseline vs actual**, §3 User Behavior, §4 Sensitive
Data Access.
> "These visuals are populated the moment we deploy. This is behaviour analytics, not just logging."

## 12:00-17:00 — Run WOW scenarios (live)
```powershell
./scripts/generate-wow-detections.ps1 -Target Azure -RunAi
```
Triggers, in order: **1** DBA after-hours VIP data · **3** suspicious DELETE · **4** permission
escalation · **5** break-glass · **6** query volume spike. Each prints what it does, why it matters,
the validation KQL, workbook section and alert name.

## 17:00-21:00 — Anomaly detections
Workbook §6 WOW Detections + §7 Investigation View (DetectionName, RiskCategory, **AnomalyScore**,
BehaviorExplanation). Run from `kql/anomaly-detections-kql-ml.kql` (e.g. Detection A volume anomaly,
Detection C after-hours).
> "We are not only checking static rules. The PoC looks for deviations from expected behaviour:
> unusual table, timing, volume, and role-to-data relationship."

## 21:00-25:00 — AI-assisted investigation
```powershell
./scripts/run-ai-analysis.ps1
```
Show `outputs/demo-ai-summary.md`: top risky user, why the alert triggered, evidence cited,
recommended next step.
> "The AI layer does not replace audit or detection. It explains the evidence and helps an analyst
> understand what to investigate first — read-only, grounded in the data, no invented events."

## 25:00-28:00 — Alerting & SOC handoff
Monitor → Alerts (7 rules, 5-min cadence) + Action Group email. If enabled, show Sentinel §8 in the
workbook.
> "In production these alerts feed SOC processes. Sentinel UEBA enriches identity/entity context
> when enabled with supported data sources."

## 28:00-30:00 — Close / production discussion
Retention, RBAC, query-text sensitivity, cost, production rollout, Sentinel/UEBA, AI governance.
> "This PoC shows Contoso Bank can move from database audit logging to database **behaviour analytics**:
> who accessed what, whether it was expected, and why it matters."

## Fallbacks
Alerts run every 5 minutes. If one has not fired, run its KQL directly (see
[demo-speaker-notes.md](demo-speaker-notes.md) and `kql/deterministic-detections.kql` /
`kql/anomaly-detections-kql-ml.kql`). The preloaded history guarantees the workbook is populated
even before any live scenario runs.
