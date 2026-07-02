<#
.SYNOPSIS
  Generates the Contoso Bank WOW demo scenarios (0-10) that drive the deterministic and
  behavioural anomaly detections, and (optionally) the AI explanation.
.DESCRIPTION
  Each scenario prints: name, what it does, why it matters, the expected KQL
  validation query, the expected workbook section, and the expected alert name.
  All actions are non-destructive (DELETEs run inside a rolled-back transaction and
  only target demo rows). Safe to run repeatedly.
.PARAMETER Target
  Azure | Vm | Both (default Azure).
.PARAMETER RunAi
  Also run Scenario 10 (AI explanation) via run-ai-analysis.ps1.
.EXAMPLE
  ./scripts/generate-wow-detections.ps1 -Target Azure -RunAi
#>
[CmdletBinding()]
param(
    [ValidateSet('Azure','Vm','Both')][string]$Target = 'Both',
    [string]$DemoUserPassword = 'P0c-Demo!User2026',
    [int]$VolumeLoopCount = 60,
    [switch]$SkipBaseline,
    [switch]$RunAi
)

. "$PSScriptRoot\_common.ps1"
$targets = Get-PocTargets -Target $Target
if (-not $targets) { throw "No demo databases resolved. Run 'azd up' and the setup scripts first." }

function Show-ScenarioMeta {
    param([string]$Name, [string]$Doing, [string]$Matters, [string]$Kql, [string]$Section, [string]$Alert)
    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor DarkCyan
    Write-Host "  $Name" -ForegroundColor Cyan
    Write-Host "  Doing   : $Doing" -ForegroundColor Gray
    Write-Host "  Matters : $Matters" -ForegroundColor Gray
    Write-Host "  Workbook: $Section" -ForegroundColor DarkGray
    Write-Host "  Alert   : $Alert" -ForegroundColor DarkGray
    Write-Host "  Validate: $Kql" -ForegroundColor DarkYellow
    Write-Host ("=" * 80) -ForegroundColor DarkCyan
}

function Log-DemoEvent {
    param($Target, [string]$Code, [string]$Name, [string]$RunBy)
    Invoke-DemoQuery -Target $Target -User 'privileged_admin' -Password $DemoUserPassword `
        -Query "INSERT INTO auditdemo.DemoEvents (ScenarioCode, ScenarioName, RunBy, Notes) VALUES ('$Code', N'$Name', '$RunBy', N'generate-wow-detections.ps1');" | Out-Null
}

# Temporarily open the VM SQL port only when a VM target is in scope.
$vmTargeted = [bool]($targets | Where-Object { $_.Name -eq 'SqlServerVM' })
if ($vmTargeted) { Open-PocVmSqlPort -PocEnv (Get-PocEnv) }

try {
foreach ($t in $targets) {
    Write-Host ""
    Write-Host "################  TARGET: $($t.Name)  ################" -ForegroundColor Magenta

    # ---- Scenario 0: baseline normal activity -------------------------------
    if (-not $SkipBaseline) {
        Show-ScenarioMeta -Name "Scenario 0 - Baseline normal activity" `
            -Doing "In-role reads/writes by normal_user, app_user, payments_analyst, fraud_analyst, dba_user" `
            -Matters "Establishes a healthy behavioural baseline so anomalies stand out" `
            -Kql "UnifiedSqlAudit | where EventTime > ago(30m) | summarize count() by UserName" `
            -Section "2. Data Access Behavior Timeline" -Alert "(none - baseline)"
        Invoke-DemoQuery -Target $t -User 'normal_user'      -Password $DemoUserPassword -Query "SELECT TOP 25 CustomerId, City FROM core.Customers;" | Out-Null
        Invoke-DemoQuery -Target $t -User 'app_user'         -Password $DemoUserPassword -Query "INSERT INTO payments.Transactions (AccountId,TransactionType,Amount,Currency,MerchantName,MerchantCategory,CounterpartyAccount,TransactionDate,Channel,RiskFlag) VALUES ((SELECT TOP 1 AccountId FROM core.Accounts ORDER BY NEWID()),'Payment',19.90,'EUR','Spotify','Entertainment','SE0012345678',SYSUTCDATETIME(),'Mobile','None');" | Out-Null
        Invoke-DemoQuery -Target $t -User 'payments_analyst' -Password $DemoUserPassword -Query "SELECT TOP 50 TransactionId, Amount FROM payments.Transactions;" | Out-Null
        Invoke-DemoQuery -Target $t -User 'fraud_analyst'    -Password $DemoUserPassword -Query "SELECT TOP 50 SignalId, Severity FROM risk.FraudSignals;" | Out-Null
        Invoke-DemoQuery -Target $t -User 'dba_user'         -Password $DemoUserPassword -Query "SELECT TOP 25 name, type_desc FROM sys.objects WHERE is_ms_shipped=0;" | Out-Null
    }

    # ---- Scenario 1: DBA after-hours VIP sensitive access -------------------
    Show-ScenarioMeta -Name "Scenario 1 - DBA after-hours VIP sensitive data access" `
        -Doing "dba_user reads VIP salary/credit/risk fields in auditdemo.SensitiveCustomerData" `
        -Matters "Privileged access is allowed, but this timing + data target is unusual" `
        -Kql "SQLSecurityAuditEvents | where ServerPrincipalName=='dba_user' and ObjectName has 'SensitiveCustomerData'" `
        -Section "6. WOW Detections / 7. Investigation View" -Alert "SQL PoC - Privileged After-Hours Sensitive Access"
    Invoke-DemoQuery -Target $t -User 'dba_user' -Password $DemoUserPassword `
        -Query "SELECT TOP 25 CustomerId, SalaryBand, CreditScore, InternalRiskComment, VIPFlag FROM auditdemo.SensitiveCustomerData WHERE VIPFlag=1 ORDER BY CreditScore DESC;" | Out-Null
    Log-DemoEvent -Target $t -Code '1' -Name 'DBA after-hours sensitive access' -RunBy 'dba_user'

    # ---- Scenario 2: normal user attempts sensitive access ------------------
    Show-ScenarioMeta -Name "Scenario 2 - Normal user accessing sensitive table" `
        -Doing "normal_user queries auditdemo.SensitiveCustomerData (denied or logged)" `
        -Matters "A standard account touching privileged data is flagged instantly" `
        -Kql "SQLSecurityAuditEvents | where ServerPrincipalName=='normal_user' and Statement has 'SensitiveCustomerData'" `
        -Section "6. WOW Detections" -Alert "SQL PoC - Sensitive Table Access by Non-Privileged User"
    Invoke-DemoQuery -Target $t -User 'normal_user' -Password $DemoUserPassword `
        -Query "SELECT TOP 10 CustomerId, SalaryBand, CreditScore FROM auditdemo.SensitiveCustomerData;" | Out-Null
    Log-DemoEvent -Target $t -Code '2' -Name 'Normal user accessing sensitive table' -RunBy 'normal_user'

    # ---- Scenario 3: suspicious DELETE on wire transfers (safe) -------------
    Show-ScenarioMeta -Name "Scenario 3 - Suspicious DELETE against financial transaction object" `
        -Doing "suspicious_user DELETEs demo rows in payments.WireTransfers inside a rolled-back tran" `
        -Matters "Destructive statements against money-movement data are high risk" `
        -Kql "SQLSecurityAuditEvents | where Statement has 'DELETE' and Statement has 'WireTransfers'" `
        -Section "6. WOW Detections" -Alert "SQL PoC - High-Risk SQL Statement"
    Invoke-DemoQuery -Target $t -User 'suspicious_user' -Password $DemoUserPassword `
        -Query "BEGIN TRAN; DELETE FROM payments.WireTransfers WHERE IsDemoRow=1 AND WireId IN (SELECT TOP 3 WireId FROM payments.WireTransfers WHERE IsDemoRow=1 ORDER BY WireId DESC); ROLLBACK TRAN;" | Out-Null
    Log-DemoEvent -Target $t -Code '3' -Name 'Suspicious DELETE against financial object' -RunBy 'suspicious_user'

    # ---- Scenario 4: permission escalation ----------------------------------
    Show-ScenarioMeta -Name "Scenario 4 - Permission escalation / role membership change" `
        -Doing "privileged_admin GRANTs then REVOKEs SELECT on risk.SanctionsScreening to suspicious_user" `
        -Matters "Who grants access to whom, and when, must be captured" `
        -Kql "SQLSecurityAuditEvents | where Statement matches regex @'(?i)\b(GRANT|REVOKE)\b' and Statement has 'suspicious_user'" `
        -Section "6. WOW Detections" -Alert "SQL PoC - Permission Escalation"
    Invoke-DemoQuery -Target $t -User 'privileged_admin' -Password $DemoUserPassword -Query "GRANT SELECT ON OBJECT::risk.SanctionsScreening TO suspicious_user;" | Out-Null
    Invoke-DemoQuery -Target $t -User 'privileged_admin' -Password $DemoUserPassword -Query "REVOKE SELECT ON OBJECT::risk.SanctionsScreening TO suspicious_user;" | Out-Null
    Log-DemoEvent -Target $t -Code '4' -Name 'Permission escalation' -RunBy 'privileged_admin'

    # ---- Scenario 5: break-glass usage --------------------------------------
    Show-ScenarioMeta -Name "Scenario 5 - Break-glass account used" `
        -Doing "breakglass_admin reads admin.AccessRequests" `
        -Matters "Emergency accounts should almost never be used - alert immediately" `
        -Kql "SQLSecurityAuditEvents | where ServerPrincipalName=='breakglass_admin'" `
        -Section "6. WOW Detections" -Alert "SQL PoC - Break-glass Account Used"
    Invoke-DemoQuery -Target $t -User 'breakglass_admin' -Password $DemoUserPassword `
        -Query "SELECT TOP 25 RequestId, RequestedBy, RequestedRole, Status FROM admin.AccessRequests ORDER BY RequestedDate DESC;" | Out-Null
    Log-DemoEvent -Target $t -Code '5' -Name 'Break-glass account used' -RunBy 'breakglass_admin'

    # ---- Scenario 6: query volume spike + high velocity enumeration ---------
    Show-ScenarioMeta -Name "Scenario 6 - Query volume anomaly + high velocity object enumeration" `
        -Doing "suspicious_user runs $VolumeLoopCount SELECTs across many distinct tables" `
        -Matters "Volume + breadth of access looks like discovery / exfiltration" `
        -Kql "SQLSecurityAuditEvents | where ServerPrincipalName=='suspicious_user' and ActionName=='BATCH COMPLETED' | summarize count() by bin(TimeGenerated,5m)" `
        -Section "2/3 timeline + 6. WOW Detections" -Alert "SQL PoC - Query Volume Spike"
    $tables = @('core.Customers','core.Accounts','core.Branches','core.Employees','risk.FraudSignals','risk.CustomerRiskScores','risk.SanctionsScreening','auditdemo.SensitiveCustomerData','auditdemo.PrivilegedOperations','auditdemo.DemoEvents')
    for ($i = 1; $i -le $VolumeLoopCount; $i++) {
        $tbl = $tables[($i - 1) % $tables.Count]
        Invoke-DemoQuery -Target $t -User 'suspicious_user' -Password $DemoUserPassword -Query "SELECT TOP 20 * FROM $tbl ORDER BY 1;" | Out-Null
        if ($i % 20 -eq 0) { Write-Host "    ...$i queries" -ForegroundColor DarkGray }
    }
    Log-DemoEvent -Target $t -Code '6' -Name 'Query volume + enumeration' -RunBy 'suspicious_user'

    # ---- Scenario 7: fraud analyst out-of-role HR/salary --------------------
    Show-ScenarioMeta -Name "Scenario 7 - Fraud analyst out-of-role HR/salary access" `
        -Doing "fraud_analyst queries hr.EmployeeAccessProfiles and salary fields" `
        -Matters "Right person, wrong data domain - segregation of duties" `
        -Kql "SQLSecurityAuditEvents | where ServerPrincipalName=='fraud_analyst' and (ObjectName has_any ('EmployeeAccessProfiles','SensitiveCustomerData'))" `
        -Section "3/7 (Out-of-role)" -Alert "(anomaly KQL - Out-of-role data access)"
    Invoke-DemoQuery -Target $t -User 'fraud_analyst' -Password $DemoUserPassword -Query "SELECT TOP 25 UserName, Department, ManagerName FROM hr.EmployeeAccessProfiles;" | Out-Null
    Invoke-DemoQuery -Target $t -User 'fraud_analyst' -Password $DemoUserPassword -Query "SELECT TOP 25 CustomerId, SalaryBand, CreditScore FROM auditdemo.SensitiveCustomerData;" | Out-Null
    Log-DemoEvent -Target $t -Code '7' -Name 'Out-of-role data access' -RunBy 'fraud_analyst'

    # ---- Scenario 8: payments analyst querying fraud/sanctions --------------
    Show-ScenarioMeta -Name "Scenario 8 - Payments analyst querying fraud/sanctions data" `
        -Doing "payments_analyst queries risk.SanctionsScreening and risk.FraudSignals" `
        -Matters "Out-of-role access to sanctions data is an insider-risk / compliance signal" `
        -Kql "SQLSecurityAuditEvents | where ServerPrincipalName=='payments_analyst' and ObjectName has_any ('SanctionsScreening','FraudSignals')" `
        -Section "7. Investigation View" -Alert "(anomaly KQL - Segregation-of-duties)"
    Invoke-DemoQuery -Target $t -User 'payments_analyst' -Password $DemoUserPassword -Query "SELECT TOP 25 ScreeningId, ListName, Decision FROM risk.SanctionsScreening; SELECT TOP 25 SignalId, SignalType FROM risk.FraudSignals;" | Out-Null
    Log-DemoEvent -Target $t -Code '8' -Name 'Segregation-of-duties anomaly' -RunBy 'payments_analyst'

    # ---- Scenario 9: first-time sensitive object access ---------------------
    Show-ScenarioMeta -Name "Scenario 9 - First-time sensitive object access" `
        -Doing "reporting_user accesses risk.CustomerRiskScores for the first time" `
        -Matters "Behaviour is compared to the user's own history - firsts stand out" `
        -Kql "SQLSecurityAuditEvents | where ServerPrincipalName=='reporting_user' and ObjectName has 'CustomerRiskScores'" `
        -Section "7. Investigation View (First-time)" -Alert "(anomaly KQL - First-time sensitive object access)"
    Invoke-DemoQuery -Target $t -User 'reporting_user' -Password $DemoUserPassword -Query "SELECT TOP 25 CustomerId, RiskScore, RiskBand FROM risk.CustomerRiskScores;" | Out-Null
    Log-DemoEvent -Target $t -Code '9' -Name 'First-time sensitive object access' -RunBy 'reporting_user'
}
}
finally {
    if ($vmTargeted) { Close-PocVmSqlPort -PocEnv (Get-PocEnv) }
}

Write-Host ""
Write-Host "WOW scenarios 0-9 generated. Audit events reach Log Analytics in ~2-5 minutes." -ForegroundColor Green

# ---- Scenario 10: AI explanation -------------------------------------------
if ($RunAi) {
    Show-ScenarioMeta -Name "Scenario 10 - AI-assisted explanation" `
        -Doing "Runs latest anomalies through the read-only AI Analyst API" `
        -Matters "AI explains WHY activity is suspicious and what to investigate first" `
        -Kql "see kql/ai-analyst-inputs.kql" -Section "5. AI-Assisted Findings" -Alert "(n/a)"
    & "$PSScriptRoot\run-ai-analysis.ps1"
} else {
    Write-Host "Tip: add -RunAi (or run ./scripts/run-ai-analysis.ps1) for Scenario 10 AI explanation." -ForegroundColor Yellow
}
Write-Host "Open the 'Contoso Bank SQL Audit & AI Behavior Analytics PoC' workbook and refresh." -ForegroundColor Yellow
