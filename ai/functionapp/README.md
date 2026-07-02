# AI Analyst API (read-only)

A lightweight **Python (v2) Azure Functions** app that provides a **read-only** AI Analyst
for the Contoso Bank SQL Audit & Behavior Analytics PoC. It is **Layer 3** — it explains evidence
produced by the deterministic (Layer 1) and KQL-ML anomaly (Layer 2) layers. It never
replaces them.

## Safety boundaries

- **Read-only.** Never executes SQL, never mutates Azure resources.
- **Grounded.** The model uses only the `evidence` sent in the request (already retrieved by
  KQL). It must not invent events and must cite `UserName, EventTime, DatabaseName,
  ObjectName, Statement, ClientIp, RiskCategory, DetectionName`.
- **No secrets.** Auth to Azure OpenAI uses the Function App's **managed identity**
  (`DefaultAzureCredential`). No keys are stored in code or app settings.
- **Content safety.** The model deployment uses the default Azure OpenAI content filter
  (`Microsoft.DefaultV2`); the system prompt also forbids secrets and destructive SQL.

## Endpoints

| Method | Route | Purpose |
|--------|-------|---------|
| GET | `/api/health` | Liveness + whether AI is configured |
| POST | `/api/analyze/anomaly` | Explain a single anomaly record (`{"evidence": {...}}`) |
| POST | `/api/analyze/daily-summary` | Executive daily risk summary (`{"evidence": {...}}`) |
| POST | `/api/kql/generate` | Generate a **read-only** KQL query (`{"question": "..."}`) |
| POST | `/api/demo/executive-summary` | 3-minute demo narrative (`{"evidence": {...}}`) |

## App settings (set by Bicep)

- `AZURE_OPENAI_ENDPOINT`, `AZURE_OPENAI_DEPLOYMENT`, `AZURE_OPENAI_API_VERSION`
- `LOG_ANALYTICS_WORKSPACE_ID` (workspace GUID, for optional in-function Logs queries)

## Deploy

Deployed automatically by `azd up` (service `aianalyst` in `azure.yaml`). To deploy code only:

```powershell
azd deploy aianalyst
```

## Local run

```powershell
pip install -r requirements.txt
func start
```

Requires `AZURE_OPENAI_ENDPOINT`/`AZURE_OPENAI_DEPLOYMENT` and an Azure login
(`az login`) with the **Cognitive Services OpenAI User** role on the target resource.

## Invoke

```powershell
$key = az functionapp keys list -g rg-sqlaudit-demo -n <funcName> --query functionKeys.default -o tsv
Invoke-RestMethod -Method Post -Uri "https://<funcName>.azurewebsites.net/api/analyze/daily-summary?code=$key" `
  -ContentType 'application/json' -Body (@{ evidence = @(@{ UserName='dba_user'; DetectionName='DBA after-hours sensitive access' }) } | ConvertTo-Json -Depth 6)
```

`../../scripts/run-ai-analysis.ps1` wraps this end-to-end (query → call → save summary).
