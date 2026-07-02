<#
.SYNOPSIS
  azd postprovision hook - prints next steps after `azd up`.
#>
. "$PSScriptRoot\_common.ps1"
$env = Get-PocEnv

Write-Host ""
Write-Host "=========================================================" -ForegroundColor Green
Write-Host "  SQL Audit PoC - infrastructure provisioned" -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Green
Write-Host "  Resource group : $($env['AZURE_RESOURCE_GROUP'])"
Write-Host "  Azure SQL      : $($env['SQL_SERVER_FQDN']) / $($env['SQL_DATABASE_NAME'])"
Write-Host "  SQL VM         : $($env['VM_NAME']) ($($env['VM_PUBLIC_IP']))"
Write-Host "  Log Analytics  : $($env['LOG_ANALYTICS_NAME'])"
Write-Host "  Key Vault      : $($env['KEY_VAULT_NAME'])"
Write-Host ""
Write-Host "  NEXT STEPS:" -ForegroundColor Yellow
Write-Host "    1) ./scripts/run-poc-scenarios.ps1 -Setup      # schema, users, audit, mock data"
Write-Host "    2) ./scripts/generate-normal-activity.ps1      # baseline"
Write-Host "    3) ./scripts/generate-wow-detections.ps1 -RunAi # WOW detections + AI"
Write-Host "    4) Open the 'Contoso Bank SQL Audit & AI Behavior Analytics PoC' workbook"
Write-Host ""
Write-Host "  See docs/post-deployment.md and docs/demo-walkthrough-30min.md." -ForegroundColor Gray
Write-Host "  Cleanup: azd down --purge" -ForegroundColor Gray

# --- Preload 90 days of demo history so the PoC is demo-ready immediately -----
Write-Host ""
Write-Host "  Preloading 90-day synthetic history + AI examples (one-time)..." -ForegroundColor Cyan
try {
    & "$PSScriptRoot\preload-historical-audit-data.ps1"
} catch {
    Write-Warning "History preload skipped: $($_.Exception.Message.Split([Environment]::NewLine)[0])"
    Write-Host "  Run it manually: ./scripts/preload-historical-audit-data.ps1" -ForegroundColor Yellow
}

# --- Create the UnifiedSqlAudit normalised view (saved function) --------------
Write-Host ""
Write-Host "  Creating UnifiedSqlAudit function (normalised view over the history)..." -ForegroundColor Cyan
try {
    & "$PSScriptRoot\create-unified-function.ps1"
} catch {
    Write-Warning "UnifiedSqlAudit creation skipped: $($_.Exception.Message.Split([Environment]::NewLine)[0])"
    Write-Host "  Run it manually: ./scripts/create-unified-function.ps1" -ForegroundColor Yellow
}
