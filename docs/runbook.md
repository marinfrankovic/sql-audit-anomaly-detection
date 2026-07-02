# Runbook

Operational runbook for the AI-Augmented SQL Audit & User Behavior Anomaly Detection PoC (Contoso Bank).

## Purpose
Demonstrate, Azure-only, end-to-end SQL audit visibility and **behavioural anomaly detection** across
Azure SQL and SQL Server on a VM, unified in Log Analytics, with three detection layers (deterministic,
KQL-ML anomaly, optional AI), preloaded 90-day history, dashboards, alerts and optional Sentinel/UEBA.

## Architecture
See [architecture.md](architecture.md).

## Prerequisites
- `azd`, `az`, PowerShell 7+; quota for one `Standard_B4ms_v2` VM and an Azure OpenAI `gpt-4o-mini`
  deployment in Sweden Central; Key Vault Secrets User for the operator.

## Deploy
```powershell
azd auth login
azd init
azd up      # provisions + deploys AI function + preloads 90-day history
```

## Configure live SQL, users, audit, data
```powershell
./scripts/run-poc-scenarios.ps1 -Setup
# or individually:
./scripts/setup-azuresql.ps1
./scripts/setup-sqlvm.ps1
./scripts/create-sql-users.ps1 -Target Both
./scripts/configure-sql-audit.ps1 -Target Both
./scripts/create-mock-data.ps1 -Target Both
```

## Preload / re-seed history (normally automatic)
```powershell
./scripts/preload-historical-audit-data.ps1        # or -Force to re-seed
```

## Validate Azure SQL audit
```kusto
SQLSecurityAuditEvents | where TimeGenerated > ago(1h)
| project TimeGenerated, DatabaseName, DatabasePrincipalName, ActionName, ObjectName, Statement
| order by TimeGenerated desc
```

## Validate SQL VM audit
```kusto
Event | where TimeGenerated > ago(1h) and Source has "MSSQL"
| project TimeGenerated, Computer, EventID, RenderedDescription | order by TimeGenerated desc
```

## Run mock activity
```powershell
./scripts/generate-normal-activity.ps1
```

## Run WOW detections (scenarios 0-10)
```powershell
./scripts/generate-wow-detections.ps1 -RunAi
```

## Run AI analysis
```powershell
./scripts/run-ai-analysis.ps1      # writes outputs/demo-ai-summary.md
```

## Open the workbook
Monitor → Workbooks → **Contoso Bank SQL Audit & AI Behavior Analytics PoC** (TimeRange 30 days).

## Validate alerts
```powershell
az monitor scheduled-query list -g rg-sqlaudit-demo --query "[].{name:name,enabled:enabled}" -o table
```

## Optional Sentinel / UEBA
- `enableSentinel=true` (default) onboards Sentinel. `enableUEBA=true` adds UEBA settings.
- Correlate: run `kql/sentinel-ueba-correlation.kql` (friendly message if UEBA empty).

## Re-run cleanly
```powershell
./scripts/cleanup-poc.ps1                 # reset demo markers, keep infra
./scripts/run-poc-scenarios.ps1 -Wow
```

## Full teardown
```powershell
azd down --purge
```

## Exact command reference
```powershell
azd auth login; azd init; azd up
./scripts/create-mock-data.ps1
./scripts/generate-normal-activity.ps1
./scripts/generate-wow-detections.ps1 -RunAi
./scripts/run-poc-scenarios.ps1
./scripts/run-ai-analysis.ps1
```

## Troubleshooting
See [troubleshooting.md](troubleshooting.md).
