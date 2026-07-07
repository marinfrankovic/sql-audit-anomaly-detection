<#
.SYNOPSIS
  Refreshes the demo by seeding a DENSE, CURRENT window of synthetic SQL audit
  activity across the PAST N days (default 7), ending TODAY. Use this right before
  a demo so the recent timeline is full and the latest anomalies are "today".
.DESCRIPTION
  The 90-day baseline seed (generate-ai-baseline-data.ps1) anchors its anomalies to
  the day it was run. If that was days ago, the recent window looks empty and the
  "major" incidents are stale. This script tops up the SAME custom table
  (SqlAuditPoC_CL) via the Azure Monitor HTTP Data Collector API with:
    * Rich normal in-role baseline for every persona, every day (business hours).
    * Escalating deviations across the recent days (rising anomaly scores).
    * A subset of "major" incidents on the last two days.
    * The full set of "major" incidents TODAY (break-glass, DBA after-hours sensitive
      access, destructive DELETE on money-movement data, permission escalation,
      enumeration/volume spike, out-of-role access).
    * Fresh AI-investigation examples (SqlAuditAI_CL) time-stamped now.
  Records use the exact field names UnifiedSqlAudit projects, so the workbook,
  alerts and detections light up identically to the baseline seed.

  ALL DATA IS SYNTHETIC. No real personal data. Safe to run repeatedly — each run
  appends a fresh batch (the Data Collector API does not de-duplicate).

  Runs against the CURRENT azd environment by default, or an explicitly supplied
  resource group + workspace (handy when there is no local azd env).
.PARAMETER Days
  Number of days to fill, ending today. Default 7.
.PARAMETER VolumeMultiplier
  Scales the per-persona baseline volume. Default 1.5 (denser than the 90-day seed).
.PARAMETER ResourceGroup
  Resource group holding the Log Analytics workspace. Falls back to the azd env
  value AZURE_RESOURCE_GROUP.
.PARAMETER WorkspaceName
  Log Analytics workspace name. Falls back to the azd env value LOG_ANALYTICS_NAME.
.PARAMETER WhatIf
  Generate and report the event counts WITHOUT posting to Log Analytics.
.EXAMPLE
  ./scripts/refresh-recent-activity.ps1 -ResourceGroup rg-vlk-sqlaudit-demo -WorkspaceName log-sqlaudit-cpyoxxywo6bi2
.EXAMPLE
  ./scripts/refresh-recent-activity.ps1              # uses the current azd environment
#>
[CmdletBinding()]
param(
    [int]$Days = 7,
    [double]$VolumeMultiplier = 1.5,
    [string]$ResourceGroup,
    [string]$WorkspaceName,
    [switch]$WhatIf
)

. "$PSScriptRoot\_common.ps1"

# --- Resolve workspace (explicit params win; else azd env) -------------------
# Only consult the azd environment when a value is actually missing. Calling
# Get-PocEnv (which runs 'azd env get-values') when there is no azd environment
# can block, so we skip it entirely once both values are supplied explicitly.
if (-not $ResourceGroup -or -not $WorkspaceName) {
    $envValues = @{}
    try { $envValues = Get-PocEnv } catch { }
    if (-not $ResourceGroup) { $ResourceGroup = $envValues['AZURE_RESOURCE_GROUP'] }
    if (-not $WorkspaceName)  { $WorkspaceName  = $envValues['LOG_ANALYTICS_NAME'] }
}
if (-not $ResourceGroup -or -not $WorkspaceName) {
    throw "Could not resolve the workspace. Pass -ResourceGroup and -WorkspaceName, or run inside an azd environment."
}

$customerId = az monitor log-analytics workspace show --resource-group $ResourceGroup --workspace-name $WorkspaceName --query customerId -o tsv 2>$null
if (-not $customerId) { throw "Could not read workspace '$WorkspaceName' in '$ResourceGroup' (need Reader + Log Analytics access)." }

$sharedKey = $null
if (-not $WhatIf) {
    $sharedKey = az monitor log-analytics workspace get-shared-keys --resource-group $ResourceGroup --workspace-name $WorkspaceName --query primarySharedKey -o tsv 2>$null
    if (-not $sharedKey) { throw "Could not retrieve the Log Analytics shared key (need Contributor on the workspace)." }
}

# --- Data Collector API signing + send (identical to the baseline seed) ------
function Send-LaData {
    param([Parameter(Mandatory)][string]$LogType, [Parameter(Mandatory)][array]$Records)
    if ($Records.Count -eq 0) { return }
    if ($WhatIf) { return }
    $body = ($Records | ConvertTo-Json -Depth 6 -AsArray)
    $bytes = [Text.Encoding]::UTF8.GetBytes($body)
    $date = [DateTime]::UtcNow.ToString('r')
    $stringToSign = "POST`n$($bytes.Length)`napplication/json`nx-ms-date:$date`n/api/logs"
    $keyBytes = [Convert]::FromBase64String($sharedKey)
    $hmac = New-Object System.Security.Cryptography.HMACSHA256
    $hmac.Key = $keyBytes
    $sig = [Convert]::ToBase64String($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($stringToSign)))
    $auth = "SharedKey ${customerId}:${sig}"
    $uri = "https://$customerId.ods.opinsights.azure.com/api/logs?api-version=2016-04-01"
    # We deliberately do NOT set 'time-generated-field'. The Data Collector API clamps
    # a back-dated TimeGenerated to ~2 days, which would collapse the window into the
    # last couple of days. EventTime (a normal datetime column, EventTime_t) is NOT
    # clamped, so we keep the true business time there and always bin history by it.
    $headers = @{ Authorization = $auth; 'Log-Type' = $LogType; 'x-ms-date' = $date }
    Invoke-RestMethod -Uri $uri -Method Post -ContentType 'application/json' -Headers $headers -Body $body | Out-Null
}

# --- Persona baseline profiles (aligned with generate-ai-baseline-data.ps1) --
$personas = @(
    @{ U='normal_user';      Priv=$false; Ip='10.42.1.20'; Vol=25; Schema='core';     Obj=@('core.Customers','core.Accounts') },
    @{ U='app_user';         Priv=$false; Ip='10.42.1.30'; Vol=40; Schema='payments'; Obj=@('payments.Transactions') },
    @{ U='reporting_user';   Priv=$false; Ip='10.42.1.40'; Vol=20; Schema='core';     Obj=@('core.Customers','payments.Transactions') },
    @{ U='payments_analyst'; Priv=$false; Ip='10.42.1.50'; Vol=22; Schema='payments'; Obj=@('payments.Transactions','payments.PaymentInstructions') },
    @{ U='fraud_analyst';    Priv=$false; Ip='10.42.1.60'; Vol=18; Schema='risk';     Obj=@('risk.FraudSignals','risk.CustomerRiskScores') },
    @{ U='dba_user';         Priv=$true;  Ip='10.42.1.70'; Vol=15; Schema='core';     Obj=@('core.Customers','payments.Transactions') }
)
$sensitiveObjs = @('SensitiveCustomerData','FraudSignals','WireTransfers','SanctionsScreening','CustomerRiskScores','EmployeeAccessProfiles','AccessRequests')

function New-Rec {
    param($When, $User, $Ip, $Obj, $Action, $Stmt, $Priv, $Score, $Detection, $Risk, $Explain, $App='SqlClient')
    $schema = ($Obj -split '\.')[0]
    $isSens = @($sensitiveObjs | Where-Object { $Obj -match $_ }).Count -gt 0
    $h = [int]$When.ToUniversalTime().Hour
    [pscustomobject]@{
        EventTime = $When.ToUniversalTime().ToString('o')
        SourceType = 'History'; ServerName = 'PocBankingAuditDb'; DatabaseName = 'PocBankingAuditDb'
        UserName = $User; ClientIp = $Ip; ApplicationName = $App
        Action = $Action; ObjectName = $Obj; SchemaName = $schema; Statement = $Stmt
        RiskCategory = $Risk; DetectionName = $Detection
        IsPrivilegedUser = $Priv; IsSensitiveObject = $isSens
        IsAfterHours = ($h -lt 6 -or $h -ge 18); AnomalyScore = $Score
        BehaviorExplanation = $Explain
    }
}

$today = (Get-Date).Date
# Seed varies per run so repeated refreshes add fresh, non-identical activity.
$rand = [Random]::new([int]((Get-Date).Ticks % [int]::MaxValue))
$totalPosted = 0
$dailyCounts = @()

Write-Host ("Refreshing the last {0} days of demo activity (multiplier x{1}) into {2}..." -f $Days, $VolumeMultiplier, $WorkspaceName) -ForegroundColor Cyan
if ($WhatIf) { Write-Host "  (WhatIf: generating counts only, nothing will be posted)" -ForegroundColor Yellow }

for ($offset = $Days - 1; $offset -ge 0; $offset--) {
    $day = $today.AddDays(-$offset)
    # Phase ramps toward today: normal early in the window, gradual mid, major at the end.
    $phase = if ($offset -eq 0) { 'major' } elseif ($offset -le 2) { 'gradual-heavy' } elseif ($offset -le 4) { 'gradual' } else { 'normal' }
    $dayRecords = New-Object System.Collections.Generic.List[object]

    # ---- Normal in-role baseline for every persona ----
    foreach ($p in $personas) {
        $isWeekend = $day.DayOfWeek -in @('Saturday','Sunday')
        $factor = if ($isWeekend) { 0.4 } else { 1.0 }
        $vol = [int]([math]::Max(4, $p.Vol * $factor * $VolumeMultiplier))
        for ($i = 0; $i -lt $vol; $i++) {
            $hour = 8 + $rand.Next(0, 9)          # business hours 08-16
            $min = $rand.Next(0, 60)
            $when = $day.AddHours($hour).AddMinutes($min)
            $obj = $p.Obj[$rand.Next(0, $p.Obj.Count)]
            $dayRecords.Add((New-Rec $when $p.U $p.Ip $obj 'BATCH COMPLETED' "SELECT ... FROM $obj" $p.Priv ($rand.Next(0,12)) 'None' 'Normal' 'in-role activity; '))
        }
    }

    # ---- Gradual deviations (rising anomaly scores toward today) ----
    if ($phase -like 'gradual*') {
        $intensity = 5 - $offset                  # bigger as we approach today
        $burst = if ($phase -eq 'gradual-heavy') { 3 + $intensity } else { 2 + $intensity }
        for ($k = 0; $k -lt $burst; $k++) {
            $when = $day.AddHours(19).AddMinutes($rand.Next(0,59))
            $dayRecords.Add((New-Rec $when 'dba_user' '10.42.1.70' 'auditdemo.SensitiveCustomerData' 'BATCH COMPLETED' 'SELECT CustomerId, SalaryBand FROM auditdemo.SensitiveCustomerData' $true (30 + $intensity*6) 'Privileged unusual object access' 'SensitiveDataAccess' 'privileged user; sensitive object; after-hours; '))
        }
        $dayRecords.Add((New-Rec ($day.AddHours(15)) 'payments_analyst' '10.42.1.50' 'risk.FraudSignals' 'BATCH COMPLETED' 'SELECT * FROM risk.FraudSignals' $false (35 + $intensity*5) 'Out-of-role data access' 'SegregationOfDuties' 'out-of-role for user; sensitive object; '))
        if ($phase -eq 'gradual-heavy') {
            # A standout incident on each of the last two days so the recent timeline is interesting.
            $dayRecords.Add((New-Rec ($day.AddHours(21).AddMinutes($rand.Next(0,59))) 'dba_user' '10.42.1.70' 'auditdemo.SensitiveCustomerData' 'BATCH COMPLETED' 'SELECT CustomerId, SalaryBand, CreditScore, InternalRiskComment FROM auditdemo.SensitiveCustomerData WHERE VIPFlag=1' $true 88 'DBA after-hours sensitive access' 'SensitiveDataAccess' 'privileged user; sensitive object; after-hours; '))
            $dayRecords.Add((New-Rec ($day.AddHours(20).AddMinutes($rand.Next(0,59))) 'fraud_analyst' '10.42.1.60' 'hr.EmployeeAccessProfiles' 'BATCH COMPLETED' 'SELECT * FROM hr.EmployeeAccessProfiles' $false 74 'Out-of-role data access' 'SegregationOfDuties' 'out-of-role for user; '))
        }
    }

    # ---- Full "major" incident set TODAY ----
    if ($phase -eq 'major') {
        $mk = {
            param($h,$u,$ip,$obj,$act,$st,$priv,$score,$det,$risk,$ex)
            $dayRecords.Add((New-Rec ($day.AddHours($h).AddMinutes($rand.Next(0,59))) $u $ip $obj $act $st $priv $score $det $risk $ex))
        }
        & $mk 22 'dba_user' '10.42.1.70' 'auditdemo.SensitiveCustomerData' 'BATCH COMPLETED' 'SELECT CustomerId, SalaryBand, CreditScore, InternalRiskComment FROM auditdemo.SensitiveCustomerData WHERE VIPFlag=1' $true 95 'DBA after-hours sensitive access' 'SensitiveDataAccess' 'privileged user; sensitive object; after-hours; '
        & $mk 23 'breakglass_admin' '10.42.1.10' 'admin.AccessRequests' 'BATCH COMPLETED' 'SELECT * FROM admin.AccessRequests' $true 100 'Break-glass account used' 'BreakGlass' 'break-glass account; '
        & $mk 21 'suspicious_user' '10.42.1.99' 'payments.WireTransfers' 'BATCH COMPLETED' 'DELETE FROM payments.WireTransfers WHERE WireId IN (...)' $false 90 'Suspicious DELETE on financial object' 'DataModification' 'high-risk statement; sensitive object; '
        & $mk 20 'privileged_admin' '10.42.1.71' 'risk.SanctionsScreening' 'PERMISSION CHANGE' 'GRANT SELECT ON risk.SanctionsScreening TO suspicious_user' $true 85 'Permission escalation' 'PermissionChange' 'permission change; '
        # Enumeration / volume spike by suspicious_user.
        foreach ($obj in @('core.Customers','core.Accounts','risk.FraudSignals','risk.SanctionsScreening','auditdemo.SensitiveCustomerData','auditdemo.PrivilegedOperations')) {
            for ($z = 0; $z -lt 12; $z++) {
                & $mk 20 'suspicious_user' '10.42.1.99' $obj 'BATCH COMPLETED' "SELECT TOP 20 * FROM $obj" $false 70 'Query volume anomaly' 'BehaviorAnomaly' 'high volume; enumeration; '
            }
        }
        & $mk 15 'fraud_analyst' '10.42.1.60' 'hr.EmployeeAccessProfiles' 'BATCH COMPLETED' 'SELECT * FROM hr.EmployeeAccessProfiles' $false 72 'Out-of-role data access' 'SegregationOfDuties' 'out-of-role for user; '
        # A couple of failed-login bursts today so the FailedLoginBurst alert has fuel.
        for ($z = 0; $z -lt 8; $z++) {
            & $mk 7 'suspicious_user' '10.42.1.99' 'core.Customers' 'LOGIN FAILED' 'Login failed for user suspicious_user' $false 65 'Failed login burst' 'AuthenticationAnomaly' 'repeated failed logins; '
        }
    }

    Send-LaData -LogType 'SqlAuditPoC' -Records $dayRecords.ToArray()
    $totalPosted += $dayRecords.Count
    $dailyCounts += [pscustomobject]@{ Day = $day.ToString('yyyy-MM-dd'); Phase = $phase; Events = $dayRecords.Count }
}

Write-Host ""
$dailyCounts | Format-Table -AutoSize
Write-Host ("{0} {1} synthetic events across the last {2} days." -f ($(if ($WhatIf) { 'Generated' } else { 'Posted' })), $totalPosted, $Days) -ForegroundColor Green

# --- Fresh AI-investigation examples time-stamped now ------------------------
$nowIso = (Get-Date).ToUniversalTime().ToString('o')
$aiExamples = @(
    @{ EventTime=$nowIso; Detection='DBA after-hours sensitive access'; UserName='dba_user';
       Finding='dba_user read VIP salary/credit/risk fields in auditdemo.SensitiveCustomerData at 22:xx UTC today, outside the expected 08-18 window. Privileged access is allowed, but the timing and VIP data target make this unusual for this user.';
       Evidence='UserName=dba_user; ObjectName=auditdemo.SensitiveCustomerData; Statement includes SalaryBand/CreditScore/InternalRiskComment; after-hours; RiskCategory=SensitiveDataAccess';
       Recommendation='Confirm an approved maintenance/task window; compare to peer DBAs; review whether VIP fields were required.' },
    @{ EventTime=$nowIso; Detection='Break-glass account used'; UserName='breakglass_admin';
       Finding='breakglass_admin was used to read admin.AccessRequests today. Break-glass accounts should only be used during an approved incident.';
       Evidence='UserName=breakglass_admin; ObjectName=admin.AccessRequests; RiskCategory=BreakGlass';
       Recommendation='Verify an approved incident record exists; rotate break-glass credentials after use.' },
    @{ EventTime=$nowIso; Detection='Suspicious DELETE on financial object'; UserName='suspicious_user';
       Finding='suspicious_user issued a DELETE against payments.WireTransfers today. Destructive statements against money-movement data are high risk.';
       Evidence='UserName=suspicious_user; ObjectName=payments.WireTransfers; Statement includes DELETE; RiskCategory=DataModification';
       Recommendation='Confirm change ticket; validate the rows targeted; review the account entitlements.' }
)
Send-LaData -LogType 'SqlAuditAI' -Records $aiExamples
if (-not $WhatIf) { Write-Host "Seeded 3 fresh AI-investigation examples (SqlAuditAI_CL) time-stamped now." -ForegroundColor Green }

Write-Host ""
Write-Host "Custom-log latency means new rows are queryable in ~2-5 minutes." -ForegroundColor DarkYellow
Write-Host "Validate: UnifiedSqlAudit | where EventTime > ago(7d) | summarize count() by bin(EventTime, 1d) | render columnchart" -ForegroundColor DarkYellow
