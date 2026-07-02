# AI-Augmented SQL Audit & User Behavior Anomaly Detection — Contoso Bank Azure PoC

A complete, deployable **proof-of-concept** proving Contoso Bank can see **who** accessed **what
database records**, **when**, **from where**, and whether the behaviour is **normal or
abnormal** — even for users with legitimate elevated access — with an **AI layer that explains
the evidence**.

Everything runs **inside Azure**, is **small and cost-conscious**, deploys with `azd up`, and is
**demo-ready immediately**: 90 days of history, behavioural baselines, anomaly scores, trend data
and AI-investigation examples are **preloaded during deployment**. No QRC, no on-premises
hardware, no Azure Arc.

> **Demo message:** _"Today we are proving that Contoso Bank can see who accessed what database records,
> when, from where, and whether the behaviour looks normal or abnormal — even when the user has
> legitimate elevated access."_

## What this repo does

- Provisions Azure SQL (auditing → Log Analytics), a Windows VM with SQL Server 2022 Developer
  (SQL Audit → App log → Azure Monitor Agent → Log Analytics), Key Vault, Action Group, **7 Log
  Search alerts**, and **two Azure Workbooks**.
- **Preloads 90 days** of synthetic FSI/banking audit history + baselines + anomaly scores + AI
  examples into a custom `SqlAuditPoC_CL` table (back-dated), unioned by `UnifiedSqlAudit`.
- Implements **three detection layers**: L1 deterministic KQL, L2 KQL-ML anomaly detection, L3
  optional read-only Azure OpenAI AI Analyst.
- Optional **Microsoft Sentinel + UEBA** for identity/entity enrichment.
- Ships a **30-minute Contoso Bank demo playbook**, speaker notes, detection catalog and validation guide.

## Architecture

```
Azure SQL ─ Auditing ─▶ SQLSecurityAuditEvents ─┐
SQL VM ─ SQL Audit ─ App Log ─ AMA ─ DCR ─▶ Event├─▶ UnifiedSqlAudit ─▶ L1/L2/L3 + Workbook + Alerts
Preloaded 90-day history ─▶ SqlAuditPoC_CL ──────┘                       └─▶ Sentinel/UEBA (optional)
```

Full details: [docs/architecture.md](docs/architecture.md). Diagram: `architecture.drawio`.

## Repository layout

```
infra/     main.bicep + modules (loganalytics, keyvault, sql-azure, sql-vm, monitoring, alerts,
           workbook, sentinel, ai-foundry-openai, functionapp-ai-analyst)
scripts/   setup, mock data, users, audit, preload-historical-audit-data, activity generators,
           run-poc-scenarios, run-ai-analysis, cleanup (+ sql/*.sql)
kql/       normalization, dashboard, deterministic-detections, anomaly-detections-kql-ml,
           sentinel-ueba-correlation, hunting, ai-analyst-inputs, demo-detections
workbooks/ SQLAuditAIBehaviorWorkbook.json
ai/        prompts/*.txt, functionapp/ (read-only AI Analyst API)
docs/      architecture, deployment-guide, post-deployment, demo-walkthrough-30min,
           demo-speaker-notes, poc-validation, detection-catalog, ai-behavior-analytics-design,
           runbook, troubleshooting, customer-facing-summary
azure.yaml Azure Developer CLI project (+ aianalyst function service)
```

## Quickstart

```powershell
azd auth login
azd init
azd env set ALERT_EMAIL you@contoso.com
azd up      # provisions everything AND preloads 90 days of history (demo-ready)
```

Then open the **Contoso Bank SQL Audit & AI Behavior Analytics PoC** workbook (Monitor → Workbooks) and
select a 30-day time range — dashboards are already populated.

To add live SQL activity for a fuller demo:

```powershell
./scripts/run-poc-scenarios.ps1 -Setup      # schema, users, audit, mock data (+ history)
./scripts/generate-wow-detections.ps1 -RunAi # WOW scenarios 0-10 + AI explanation
```

## Deployment

Parameters, prerequisites and non-azd deployment: [docs/deployment-guide.md](docs/deployment-guide.md).

**Parameters:** `environmentName`, `location`, `adminUsername`, `adminPassword`, `alertEmail`,
`sqlAdminLogin`, `sqlAdminPassword`, `enableSentinel` (default **true**), `enableUEBA` (default
false), `enableAzureOpenAI` (default **true**), `openAiModelDeploymentName` (default `gpt-4o-mini`),
`deployAiAnalystFunction` (default **true**). Admin secrets are stored in **Key Vault**.

## Running mock data & activity

```powershell
./scripts/create-mock-data.ps1                 # synthetic banking data (Azure + VM)
./scripts/generate-normal-activity.ps1         # baseline
./scripts/generate-wow-detections.ps1 -RunAi   # WOW scenarios 0-10
```

## Running AI analysis

```powershell
./scripts/run-ai-analysis.ps1     # queries anomalies, calls read-only AI Analyst, saves outputs/demo-ai-summary.md
```

## Viewing the workbook

Monitor → Workbooks → **Contoso Bank SQL Audit & AI Behavior Analytics PoC**. Sections: Executive Overview,
Data Access Behavior Timeline, User Behavior Analytics, Sensitive Data Access, AI-Assisted Findings,
WOW Detections, Investigation View, Sentinel/UEBA Context, Demo Runbook. Parameters include
TimeRange, UserName, SourceType, RiskCategory, DetectionName, DatabaseName, ShowOnlyAnomalies,
ShowAIExplanation.

## Validating alerts

```powershell
az monitor scheduled-query list --resource-group rg-sqlaudit-demo --query "[].name" -o table
```
Full validation: [docs/poc-validation.md](docs/poc-validation.md).

## Cleanup

```powershell
azd down --purge                 # delete everything
./scripts/cleanup-poc.ps1        # or reset demo markers to re-run
```

## Known limitations

- **Demo-grade security:** public network access on; secrets in Key Vault but no Private Endpoints
  (see [docs/post-deployment.md](docs/post-deployment.md)).
- **Preloaded history is synthetic** (`SqlAuditPoC_CL`), back-dated via the Logs ingestion API to
  make baselines/trends exist immediately; live platform tables cannot be back-dated.
- **UEBA is enrichment, not the primary SQL detector** — it baselines supported identity sources
  and only when Sentinel + UEBA are enabled with data.
- **AI layer is optional and read-only** — it explains evidence, never invents events, never
  executes SQL or changes Azure.
- **Impossible-travel is simulated** on client/app identity (real geo-IP is out of scope).
- Synthetic data only — no real personal data anywhere.

## License

Licensed under the [MIT License](LICENSE).
