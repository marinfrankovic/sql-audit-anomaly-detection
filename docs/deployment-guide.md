# Deployment Guide

## Prerequisites

- **Azure subscription** with rights to create the listed resources and role assignments.
- **Azure Developer CLI (azd)** — <https://aka.ms/azd-install>, **Azure CLI (az)** (`az login`).
- **PowerShell 7+**; the scripts auto-install the `SqlServer` module.
- Quota for one **Standard_B4ms_v2** VM and an **Azure OpenAI** `gpt-4o-mini` deployment in
  **Sweden Central**.
- For the AI Analyst Function, **Python 3.11** + Azure Functions Core Tools (only if deploying code
  locally; `azd up` handles it via remote build).

## 1. Authenticate

```powershell
azd auth login
az login
```

## 2. Initialise

```powershell
azd init          # environment name e.g. sqlaudit
```

## 3. Parameters

`azd up` prompts for anything without a default. Set values ahead of time if preferred:

```powershell
azd env set AZURE_LOCATION swedencentral
azd env set ALERT_EMAIL you@contoso.com
azd env set ADMIN_PASSWORD '<Strong VM admin password>'
azd env set SQL_ADMIN_PASSWORD '<Strong SQL admin password>'
# Optional toggles:
azd env set ENABLE_SENTINEL true
azd env set ENABLE_UEBA false
azd env set ENABLE_AZURE_OPENAI true
azd env set DEPLOY_AI_ANALYST_FUNCTION true
azd env set OPENAI_MODEL_DEPLOYMENT_NAME gpt-4o-mini
azd env set CLIENT_IP_ADDRESS (Invoke-RestMethod https://api.ipify.org)
```

| Parameter | azd env var | Default |
|-----------|-------------|---------|
| environmentName | `AZURE_ENV_NAME` | (prompted) |
| location | `AZURE_LOCATION` | swedencentral |
| adminPassword | `ADMIN_PASSWORD` | (prompted, secret) |
| sqlAdminPassword | `SQL_ADMIN_PASSWORD` | (prompted, secret) |
| alertEmail | `ALERT_EMAIL` | (prompted) |
| enableSentinel | `ENABLE_SENTINEL` | **true** |
| enableUEBA | `ENABLE_UEBA` | false |
| enableAzureOpenAI | `ENABLE_AZURE_OPENAI` | **true** |
| openAiModelDeploymentName | `OPENAI_MODEL_DEPLOYMENT_NAME` | gpt-4o-mini |
| deployAiAnalystFunction | `DEPLOY_AI_ANALYST_FUNCTION` | **true** |
| clientIpAddress | `CLIENT_IP_ADDRESS` | (empty) |
| vmSize | `VM_SIZE` | Standard_B4ms_v2 |

> Passwords: ≥ 12 chars incl. upper, lower, digit, symbol.

## 4. Deploy

```powershell
azd up
```

`azd up` provisions all resources, deploys the AI Analyst function code, and the **post-provision
hook preloads 90 days of history** (`preload-historical-audit-data.ps1`) — so the workbook is
populated immediately.

## 5. Add live SQL activity (optional but recommended)

```powershell
./scripts/run-poc-scenarios.ps1 -Setup       # schema, users, audit, mock data (+ history)
./scripts/generate-wow-detections.ps1 -RunAi # WOW scenarios 0-10 + AI
```

## 6. Validate

Follow [poc-validation.md](poc-validation.md).

## Non-azd deployment (infra only)

```powershell
az deployment sub create `
  --location swedencentral `
  --template-file infra/main.bicep `
  --parameters infra/main.parameters.json `
  --parameters environmentName=sqlaudit adminPassword='<...>' sqlAdminPassword='<...>' alertEmail='you@contoso.com'
# then seed history + deploy function code:
./scripts/preload-historical-audit-data.ps1
azd deploy aianalyst
```

## Cleanup

```powershell
azd down --purge
```
