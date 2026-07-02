# AI Behavior Analytics — Design & Responsible AI

## Why deterministic rules alone are insufficient

Static rules are essential and auditable, but they only catch what you thought to write down. They
struggle with **unusual-for-this-user** behaviour: a privileged user who *can* access sensitive data
but normally doesn't, a first-time access, a volume spike, or an out-of-role query. Writing a static
rule for every user × object × time × operation combination is impractical and brittle.

## Layered model (defence in depth)

| Layer | What it does | Where |
|-------|--------------|-------|
| **L1 Deterministic** | Explainable rules: failed-login burst, high-risk statements, sensitive access, break-glass, permission escalation, schema tampering | `kql/deterministic-detections.kql`, `infra/modules/alerts.bicep` |
| **L2 KQL-ML anomaly** | Per-user baselines, `make-series` + `series_decompose_anomalies`, first-time access, volume/after-hours/out-of-role/enumeration anomalies | `kql/anomaly-detections-kql-ml.kql` |
| **L3 AI explanation (optional)** | Read-only Azure OpenAI that explains anomalies, cites evidence, suggests investigation | `ai/functionapp`, `ai/prompts` |

**L1 and L2 are the source of truth. L3 only explains their output.**

## How KQL-ML anomaly detection helps

- **Baselines from history:** the preloaded 90-day `SqlAuditPoC_CL` gives each user a behavioural
  baseline immediately (no learning period).
- **`series_decompose_anomalies`** flags statistical deviations in query volume per user.
- **Baseline joins** detect first-time / rare access to sensitive objects.
- **Datatable role maps** detect out-of-role and cross-domain access without external config.

This reduces the number of static rules Contoso Bank must hand-author.

## What Microsoft Sentinel UEBA adds

Sentinel **UEBA** baselines **supported identity data sources** (Entra ID sign-ins, Azure Activity,
Security Events) and produces entity behavioural context (`BehaviorAnalytics`, investigation
priority). It is **enrichment**, correlated with SQL audit anomalies by user
(`kql/sentinel-ueba-correlation.kql`). **UEBA does not baseline `SQLSecurityAuditEvents` directly**;
do not position it as the primary SQL-audit anomaly detector. Queries use `isfuzzy=true` and return a
friendly message when UEBA tables are empty.

## What Azure OpenAI adds — and its boundaries

The AI Analyst **explains** evidence for a human analyst. It:

- **Must** use only the evidence provided (KQL output); **must not** invent events.
- **Must** cite `UserName, EventTime, DatabaseName, ObjectName, Statement, ClientIp, RiskCategory,
  DetectionName`.
- **Must** give: why suspicious, supporting evidence, a likely benign explanation, recommended
  investigation steps.
- **Must not** execute SQL, modify Azure resources, or make access decisions.
- **Must not** output secrets, connection strings, credentials or tokens.

### Grounding (avoiding hallucination)

- The system prompt fixes the analyst role and forbids invention (`ai/prompts/…`).
- The API sends **already-retrieved KQL rows** as the sole evidence; prompts are bounded in size.
- Low temperature (0.0-0.1) for factual, deterministic output.
- The model runs read-only with a **managed identity** (Cognitive Services OpenAI User) — no keys.

### Content safety

- The model deployment uses the default Azure OpenAI content filter (`Microsoft.DefaultV2`).
- The KQL-generation endpoint is constrained to **read-only** queries and forbids destructive/T-SQL
  output.

## Data privacy & query-text sensitivity

- All demo data is **synthetic**; no real personal data.
- Audit **Statement** text can contain sensitive values in production. Mitigations: restrict
  workspace RBAC, mask/redact before sending to AI, keep AI in the same tenant/region, avoid logging
  prompts/outputs containing sensitive data.
- The Function App stores **no secrets**; app settings hold only the OpenAI endpoint/deployment.

## Production considerations

- **Model choice:** `gpt-4o-mini` for cost; upgrade per accuracy/latency needs.
- **Logging & review:** capture prompts/outputs to a governed store with retention and access
  controls; human review of AI conclusions before action.
- **Access:** least-privilege managed identity; private networking (Private Endpoints) for OpenAI,
  Function and Log Analytics.
- **Governance:** align to Responsible AI standards; document that AI is advisory and read-only.
- **Evaluation:** periodically test AI explanations against known-labelled anomalies for drift.
