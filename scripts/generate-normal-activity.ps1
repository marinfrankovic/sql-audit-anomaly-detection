<#
.SYNOPSIS
  Generates realistic NORMAL business activity (baseline) - Scenarios A and B.
.DESCRIPTION
  Produces attributed audit records so the demo has a healthy baseline before the
  WOW detections. Safe to run repeatedly.
.PARAMETER Target
  Azure | Vm | Both (default Azure).
.EXAMPLE
  ./scripts/generate-normal-activity.ps1 -Target Azure
#>
[CmdletBinding()]
param(
    [ValidateSet('Azure','Vm','Both')][string]$Target = 'Both',
    [string]$DemoUserPassword = 'P0c-Demo!User2026'
)

. "$PSScriptRoot\_common.ps1"
$targets = Get-PocTargets -Target $Target
if (-not $targets) { throw "No demo databases resolved. Run 'azd up' and the setup scripts first." }

# Temporarily open the VM SQL port only when a VM target is in scope.
$vmTargeted = [bool]($targets | Where-Object { $_.Name -eq 'SqlServerVM' })
if ($vmTargeted) { Open-PocVmSqlPort -PocEnv (Get-PocEnv) }

try {
foreach ($t in $targets) {
    Write-Scenario "Scenario A - Normal business activity ($($t.Name))" "Everyday, in-role queries from standard users."

    Write-Host "  normal_user reads Customers..." -ForegroundColor Gray
    Invoke-DemoQuery -Target $t -User 'normal_user' -Password $DemoUserPassword `
        -Query "SELECT TOP 50 CustomerId, CustomerNumber, City, KycStatus FROM core.Customers ORDER BY CustomerId;" | Out-Null

    Write-Host "  app_user inserts a Transaction..." -ForegroundColor Gray
    Invoke-DemoQuery -Target $t -User 'app_user' -Password $DemoUserPassword `
        -Query "INSERT INTO payments.Transactions (AccountId, TransactionType, Amount, Currency, MerchantName, MerchantCategory, CounterpartyAccount, TransactionDate, Channel, RiskFlag) VALUES ((SELECT TOP 1 AccountId FROM core.Accounts ORDER BY NEWID()), 'Payment', 42.50, 'EUR', 'Spotify', 'Entertainment', 'SE0012345678', SYSUTCDATETIME(), 'Mobile', 'None');" | Out-Null

    Write-Host "  payments_analyst reads Transactions..." -ForegroundColor Gray
    Invoke-DemoQuery -Target $t -User 'payments_analyst' -Password $DemoUserPassword `
        -Query "SELECT TOP 100 TransactionId, Amount, Currency, MerchantCategory FROM payments.Transactions WHERE RiskFlag = 'None' ORDER BY TransactionDate DESC;" | Out-Null

    Write-Host "  fraud_analyst reads FraudSignals..." -ForegroundColor Gray
    Invoke-DemoQuery -Target $t -User 'fraud_analyst' -Password $DemoUserPassword `
        -Query "SELECT TOP 50 SignalId, SignalType, Severity FROM risk.FraudSignals ORDER BY DetectedDate DESC;" | Out-Null

    Write-Scenario "Scenario B - Privileged DBA legitimate work ($($t.Name))" "In-scope DBA maintenance activity (metadata, indexes, counts)."

    Write-Host "  dba_user reads metadata..." -ForegroundColor Gray
    Invoke-DemoQuery -Target $t -User 'dba_user' -Password $DemoUserPassword `
        -Query "SELECT TOP 50 name, type_desc, create_date FROM sys.objects WHERE is_ms_shipped = 0 ORDER BY create_date DESC;" | Out-Null

    Write-Host "  dba_user checks indexes..." -ForegroundColor Gray
    Invoke-DemoQuery -Target $t -User 'dba_user' -Password $DemoUserPassword `
        -Query "SELECT TOP 50 i.name AS IndexName, OBJECT_NAME(i.object_id) AS TableName, i.type_desc FROM sys.indexes i WHERE i.object_id > 100;" | Out-Null

    Write-Host "  dba_user checks table counts..." -ForegroundColor Gray
    Invoke-DemoQuery -Target $t -User 'dba_user' -Password $DemoUserPassword `
        -Query "SELECT COUNT(*) AS Customers FROM core.Customers; SELECT COUNT(*) AS Transactions FROM payments.Transactions;" | Out-Null
}
}
finally {
    if ($vmTargeted) { Close-PocVmSqlPort -PocEnv (Get-PocEnv) }
}

Write-Host ""
Write-Host "Normal activity generated. Validate with:" -ForegroundColor Green
Write-Validation "SQLSecurityAuditEvents`n| where TimeGenerated > ago(30m)`n| summarize Events=count() by ServerPrincipalName`n| order by Events desc"
