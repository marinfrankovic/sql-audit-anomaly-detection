# Troubleshooting

## MCAPS / SFI deny policies (Microsoft internal subscriptions)

On MCAPS / SFI-governed subscriptions, `MCAPSGovDenyPolicies` blocks several PoC patterns:

- **Azure SQL requires Entra-only auth** (`AzureSQL_WithoutAzureADOnlyAuthentication_Deny`). SQL
  admin login/password is denied. Options: deploy to a non-SFI subscription, request an RG-scoped
  policy exemption, or redesign to `azureADOnlyAuthentication=true` with an Entra admin (note: this
  degrades the per-SQL-login persona demo — run personas on the VM SQL Server instead, which is IaaS
  and not subject to this policy).
- **Function storage file share blocked (403)** — SFI storage policy denies shared-key/public
  storage that the Consumption plan needs. Set `DEPLOY_AI_ANALYST_FUNCTION=false` (the AI examples
  are preloaded and Azure OpenAI still deploys), or use Flex Consumption with identity-based storage.
- **VM size** — this region does not offer `B*ms_v2`. Use `Standard_B4s_v2` (default) or
  `Standard_B2s_v2`.
- **VM public IP / open management ports** may also be denied — front the VM with Bastion / private
  networking on SFI subscriptions.

Diagnose the exact policy: `az deployment operation sub list --name <deploymentName> --query "[?properties.provisioningState=='Failed'].properties.statusMessage"`.

## azd up / deployment

**Password policy (`InvalidTemplateDeployment`)** — Azure SQL/Windows need ≥12 chars, 3 of 4
categories: `azd env set SQL_ADMIN_PASSWORD '<stronger>'; azd env set ADMIN_PASSWORD '<stronger>'; azd up`.

**VM size not available (`SkuNotAvailable`)** — v1 B-series isn't in Sweden Central. Use a v2 size:
`azd env set VM_SIZE Standard_B4s_v2; azd up`.

**Azure OpenAI quota / model unavailable** — `gpt-4o-mini` may need capacity in the region. Check:
`az cognitiveservices account list-skus -l swedencentral -o table`. Lower capacity in
`infra/modules/ai-foundry-openai.bicep` (param `capacity`) or set `ENABLE_AZURE_OPENAI=false` to skip
the AI layer (the demo still works). Register the provider: `az provider register --namespace Microsoft.CognitiveServices`.

**Function app deploy fails (Oryx build)** — ensure `ai/functionapp/requirements.txt` is present and
Python 3.11; retry `azd deploy aianalyst`. The function is optional: `DEPLOY_AI_ANALYST_FUNCTION=false`.

**Key Vault name soft-deleted** — `az keyvault purge --name <kv> --location swedencentral` or change env name.

**Sentinel onboarding conflict** — if the workspace already had Sentinel, the solution/onboarding is
idempotent; re-run `azd up`. Set `ENABLE_SENTINEL=false` to skip.

## Preloaded history

**`SqlAuditPoC_CL` empty** — the post-provision hook may have been skipped. Run
`./scripts/preload-historical-audit-data.ps1`. First ingestion has ~2-5 min latency. Needs the
workspace **shared key** (Contributor on the workspace). Re-seed with `-Force`.

**History duplicated** — re-running without the guard appends. Use `azd down`/re-deploy for a clean
table, or query with a time filter.

## Key Vault access denied
`az role assignment create --assignee (az ad signed-in-user show --query id -o tsv) --role "Key Vault Secrets User" --scope (az keyvault show -n <kv> -g rg-sqlaudit-demo --query id -o tsv)` (allow a few minutes to propagate).

## Cannot connect to Azure SQL
- Firewall: set `CLIENT_IP_ADDRESS` (redeploy) or add your IP with `az sql server firewall-rule create`.
- Serverless DB may be paused — the first connection resumes it.

## Cannot connect to the SQL VM
- Run `setup-sqlvm.ps1` first (enables SQL auth, creates login/DB). NSG allows 1433 only from
  `CLIENT_IP_ADDRESS` (or Internet if unset). Scripts use `-TrustServerCertificate`.

## No rows in SQLSecurityAuditEvents / Event
- Run activity scripts first; auditing records real actions. Allow 1-5 min. The `Event` table needs
  the AMA extension + DCR association (`az vm extension list`, `az monitor data-collection rule association list`).

## UnifiedSqlAudit "function not found"
Save it (post-deployment §5) or paste `kql/normalization.kql` body in place of `UnifiedSqlAudit`.
The workbook core visuals union `SqlAuditPoC_CL` inline and don't require the function.

## AI Analyst call fails
- Managed-identity role propagation (Cognitive Services OpenAI User + Log Analytics Reader) can take a
  few minutes. Verify: `az role assignment list --assignee <funcPrincipalId> -o table`.
- Check app settings `AZURE_OPENAI_ENDPOINT`/`AZURE_OPENAI_DEPLOYMENT`.
- If disabled, `run-ai-analysis.ps1` falls back to the preloaded `outputs/demo-ai-summary.md`.

## Alerts not firing
5-min cadence — wait a full interval. Verify rules enabled (validation §14). Use
`kql/deterministic-detections.kql` / `kql/anomaly-detections-kql-ml.kql` to show triggering events
immediately. Confirm the Action Group email confirmation was accepted.

## Reset / re-run
```powershell
./scripts/cleanup-poc.ps1
./scripts/run-poc-scenarios.ps1 -Wow
```
