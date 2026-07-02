# AI-Augmented SQL Audit & Behavior Analytics — Customer Summary (Contoso Bank)

## The business problem

Contoso Bank must demonstrate, for audit, compliance and insider-risk, that it can answer a simple question
about database access: **was this behaviour normal or abnormal — even when the user was allowed to
do it?** Traditional audit logging tells you an action happened; it does not tell you whether the
action was *expected* for that user, object, time, or volume.

## What this PoC proves

After a single `azd up`, Contoso Bank can see, for every database action:

- **Who** executed the query, **when**, and **from where**.
- **Which** database and object (record set) were accessed, and the **statement** executed.
- Whether the user is **privileged** and whether the object is **sensitive**.
- Whether the behaviour is **normal or abnormal**, and whether that verdict came from a **static
  rule** or a **behavioural anomaly**.
- **Why** the AI analyst considered it suspicious, the **evidence**, and the **recommended
  investigation action**.

The environment is **demo-ready immediately**: 90 days of history, baselines, anomaly scores and AI
examples are preloaded — nothing has to "learn" during the meeting.

## Architecture (Azure-only, cost-conscious)

- **Azure SQL Database** → Azure SQL Auditing → Log Analytics.
- **SQL Server on an Azure VM** (represents on-prem) → SQL Server Audit → Windows Event Log → Azure
  Monitor Agent → Log Analytics.
- **Log Analytics** normalizes everything into `UnifiedSqlAudit` and drives dashboards, alerts and
  three detection layers.
- **Optional** Microsoft Sentinel + UEBA (identity enrichment) and Azure OpenAI (read-only AI
  explanation).

## Three detection layers

1. **Deterministic** rules — auditable, explainable controls.
2. **Behavioural anomaly** detection in KQL — baselines, volume, timing, role-to-data mismatch.
3. **AI explanation** — grounded, read-only summaries of the evidence for analysts.

## Demo scenarios (10)

DBA after-hours sensitive access · normal user reaching sensitive data · suspicious DELETE on wire
transfers · permission escalation · break-glass usage · query-volume spike / enumeration · fraud
analyst reaching HR/salary · payments analyst reaching sanctions data · first-time sensitive access ·
AI-assisted explanation.

## Value for Contoso Bank

- **Insider-risk & privileged-access assurance** without blocking legitimate work.
- **Segregation-of-duties** detection across payments, risk, HR and admin domains.
- **Faster investigation** — analysts get explained evidence and next steps, not just raw logs.
- **Compliance-ready** audit trail from cloud and server SQL in one place.

## Production next steps

Private networking, Entra-only SQL auth, Microsoft Defender for SQL, longer retention/archival,
Sentinel analytics + UEBA, SOC automation, and AI governance (logging, review, least-privilege).

## Not in scope for this PoC

QRC, on-premises hardware, and Azure Arc are intentionally excluded. Preloaded history is synthetic
(no real personal data); the AI layer is advisory and read-only.
