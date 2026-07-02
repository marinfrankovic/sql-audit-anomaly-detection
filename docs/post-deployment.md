# Post-Deployment Steps

After `azd up` completes, the environment is already **demo-ready** (90-day history preloaded).
These steps finish the optional live activity and hardening.

## 1. Confirm outputs

```powershell
azd env get-values
```
Confirm `SQL_SERVER_FQDN`, `VM_NAME`, `VM_PUBLIC_IP`, `LOG_ANALYTICS_NAME`, `LOG_ANALYTICS_CUSTOMER_ID`,
`KEY_VAULT_NAME`, `AZURE_OPENAI_ENDPOINT`, `AI_ANALYST_FUNCTION_URL`.

## 2. Confirm the preloaded history

```kusto
SqlAuditPoC_CL | summarize count() by bin(TimeGenerated, 1d) | render columnchart
```
If empty (e.g. the hook was skipped), run:
```powershell
./scripts/preload-historical-audit-data.ps1
```
Custom-log ingestion has ~2-5 min latency the first time.

## 3. Grant yourself Key Vault access

```powershell
$kv = (azd env get-values | Select-String KEY_VAULT_NAME).ToString().Split('=')[1].Trim('"')
$rg = (azd env get-values | Select-String AZURE_RESOURCE_GROUP).ToString().Split('=')[1].Trim('"')
az role assignment create --assignee (az ad signed-in-user show --query id -o tsv) `
  --role "Key Vault Secrets User" `
  --scope (az keyvault show -n $kv -g $rg --query id -o tsv)
```

## 4. Configure live SQL + data

```powershell
./scripts/run-poc-scenarios.ps1 -Setup
```

## 5. Save the UnifiedSqlAudit function (recommended)

Portal → Log Analytics → **Logs** → paste the body of [../kql/normalization.kql](../kql/normalization.kql)
→ **Save as function** `UnifiedSqlAudit` (category `SQLAuditPoC`). Dashboard/hunting queries and the
advanced workbook views then use it. (The workbook's core visuals already union `SqlAuditPoC_CL`
inline, so they work without the function.)

## 6. Open the workbooks

Monitor → Workbooks → **Contoso Bank SQL Audit & AI Behavior Analytics PoC** (TimeRange = 30 days).

## 7. AI Analyst

```powershell
./scripts/run-ai-analysis.ps1
```
First call requires the function's managed identity to have propagated the **Cognitive Services
OpenAI User** and **Log Analytics Reader** roles (assigned by Bicep; allow a few minutes).

## 8. Confirm the Action Group email
Accept the first-time confirmation sent to `ALERT_EMAIL`.

## 9. Hardening before any non-demo use

- Set `CLIENT_IP_ADDRESS` and redeploy to restrict RDP/1433.
- Private Endpoints + Private DNS for SQL, OpenAI, Function, Log Analytics; disable public access.
- Entra-only SQL auth; Microsoft Defender for SQL.
- Key Vault purge protection + firewall.
- Longer Log Analytics retention/archive; AI prompt/output governance (see
  [ai-behavior-analytics-design.md](ai-behavior-analytics-design.md)).

## Latency expectations
- Azure SQL → `SQLSecurityAuditEvents`: ~1-5 min. VM audit → `Event`: ~2-5 min. Custom history →
  `SqlAuditPoC_CL`: ~2-5 min (first ingestion). Alerts evaluate every 5 min.
