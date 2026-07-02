<#
.SYNOPSIS
  Preloads 90 days of SYNTHETIC SQL audit history, behavioural baselines, anomaly
  scores, trend data and AI-investigation examples into Log Analytics so the PoC is
  DEMO-READY immediately after deployment - no waiting for ML to "learn".
.DESCRIPTION
  Real platform tables (SQLSecurityAuditEvents / Event) cannot be back-dated, so this
  script ingests a PRE-NORMALIZED custom table `SqlAuditPoC_CL` via the Azure Monitor
  HTTP Data Collector API with back-dated TimeGenerated values:
    * Days 1-85  : normal in-role behaviour (baseline).
    * Days 86-90 : gradual behavioural deviations (rising anomaly scores).
    * Current day: major anomalies (break-glass, DBA after-hours, DELETE, escalation...).
  UnifiedSqlAudit unions this table, so dashboards, baselines and anomaly detections are
  populated instantly. It also seeds AI-investigation examples (`SqlAuditAI_CL`) and writes
  outputs/demo-ai-summary.md and outputs/demo-baseline.md.
  ALL DATA IS SYNTHETIC. No real personal data.
.PARAMETER Force
  Re-seed even if history already appears present.
.EXAMPLE
  ./scripts/generate-ai-baseline-data.ps1
#>
[CmdletBinding()]
param(
    [switch]$Force,
    [int]$Days = 90
)

. "$PSScriptRoot\_common.ps1"
$env = Get-PocEnv
$customerId = $env['LOG_ANALYTICS_CUSTOMER_ID']
$rg  = $env['AZURE_RESOURCE_GROUP']
$law = $env['LOG_ANALYTICS_NAME']
if (-not $customerId) { throw "LOG_ANALYTICS_CUSTOMER_ID not found. Run 'azd up' first." }

# --- Shared key for the Data Collector API ----------------------------------
$sharedKey = az monitor log-analytics workspace get-shared-keys --resource-group $rg --workspace-name $law --query primarySharedKey -o tsv 2>$null
if (-not $sharedKey) { throw "Could not retrieve Log Analytics shared key (need Contributor on the workspace)." }

# --- Idempotency guard ------------------------------------------------------
if (-not $Force) {
    try {
        $existing = az monitor log-analytics query --workspace $customerId `
            --analytics-query "SqlAuditPoC_CL | where TimeGenerated > ago(80d) | count" -o json 2>$null | ConvertFrom-Json
        $c = 0; if ($existing) { try { $c = [int](@($existing)[0].Count) } catch { $c = 0 } }
        if ($c -gt 0) { Write-Host "History already present ($c rows). Use -Force to re-seed." -ForegroundColor Yellow; return }
    } catch { <# table not created yet - proceed #> }
}

# --- Data Collector API signing + send --------------------------------------
function Send-LaData {
    param([Parameter(Mandatory)][string]$LogType, [Parameter(Mandatory)][array]$Records)
    if ($Records.Count -eq 0) { return }
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
    # NOTE: We deliberately do NOT set 'time-generated-field'. The Data Collector API
    # clamps a back-dated TimeGenerated to ~2 days, which would collapse 90 days of
    # history into the last few days. Instead we keep EventTime as a normal datetime
    # column (EventTime_t), which is NOT clamped and preserves the full 90-day span.
    # TimeGenerated therefore reflects ingestion time; always bin history by EventTime_t.
    $headers = @{ Authorization = $auth; 'Log-Type' = $LogType; 'x-ms-date' = $date }
    Invoke-RestMethod -Uri $uri -Method Post -ContentType 'application/json' -Headers $headers -Body $body | Out-Null
}

# --- Persona baseline profiles ----------------------------------------------
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
$rand = [Random]::new(20260701)
$totalPosted = 0

Write-Host "Generating $Days days of synthetic history (this is a one-time seed)..." -ForegroundColor Cyan
for ($offset = $Days - 1; $offset -ge 0; $offset--) {
    $day = $today.AddDays(-$offset)
    # Phase: normal (>=5 days ago), gradual (1-4 days ago), major (today).
    $phase = if ($offset -eq 0) { 'major' } elseif ($offset -le 4) { 'gradual' } else { 'normal' }
    $dayRecords = New-Object System.Collections.Generic.List[object]

    foreach ($p in $personas) {
        # Slightly higher weekday volume, lower on weekends.
        $isWeekend = $day.DayOfWeek -in @('Saturday','Sunday')
        $factor = 1.0; if ($isWeekend) { $factor = 0.4 }
        $vol = [int]([math]::Max(3, $p.Vol * $factor))
        for ($i = 0; $i -lt $vol; $i++) {
            $hour = 8 + $rand.Next(0, 9)           # business hours 08-16
            $min = $rand.Next(0, 60)
            $when = $day.AddHours($hour).AddMinutes($min)
            $obj = $p.Obj[$rand.Next(0, $p.Obj.Count)]
            $dayRecords.Add((New-Rec $when $p.U $p.Ip $obj 'BATCH COMPLETED' "SELECT ... FROM $obj" $p.Priv ($rand.Next(0,12)) 'None' 'Normal' 'in-role activity; '))
        }
    }

    if ($phase -eq 'gradual') {
        # Rising deviations over days 86-90: creeping after-hours + occasional out-of-role.
        $intensity = 5 - $offset   # offset 4->1 ... today handled separately
        for ($k = 0; $k -lt (2 + $intensity); $k++) {
            $when = $day.AddHours(19).AddMinutes($rand.Next(0,59))
            $dayRecords.Add((New-Rec $when 'dba_user' '10.42.1.70' 'auditdemo.SensitiveCustomerData' 'BATCH COMPLETED' 'SELECT CustomerId, SalaryBand FROM auditdemo.SensitiveCustomerData' $true (30 + $intensity*6) 'Privileged unusual object access' 'SensitiveDataAccess' 'privileged user; sensitive object; after-hours; '))
        }
        $dayRecords.Add((New-Rec ($day.AddHours(15)) 'payments_analyst' '10.42.1.50' 'risk.FraudSignals' 'BATCH COMPLETED' 'SELECT * FROM risk.FraudSignals' $false (35 + $intensity*5) 'Out-of-role data access' 'SegregationOfDuties' 'out-of-role for user; sensitive object; '))
    }

    if ($phase -eq 'major') {
        $mk = {
            param($h,$u,$ip,$obj,$act,$st,$priv,$score,$det,$risk,$ex)
            $dayRecords.Add((New-Rec ($day.AddHours($h).AddMinutes($rand.Next(0,59))) $u $ip $obj $act $st $priv $score $det $risk $ex))
        }
        & $mk 22 'dba_user' '10.42.1.70' 'auditdemo.SensitiveCustomerData' 'BATCH COMPLETED' 'SELECT CustomerId, SalaryBand, CreditScore, InternalRiskComment FROM auditdemo.SensitiveCustomerData WHERE VIPFlag=1' $true 95 'DBA after-hours sensitive access' 'SensitiveDataAccess' 'privileged user; sensitive object; after-hours; '
        & $mk 23 'breakglass_admin' '10.42.1.10' 'admin.AccessRequests' 'BATCH COMPLETED' 'SELECT * FROM admin.AccessRequests' $true 100 'Break-glass account used' 'BreakGlass' 'break-glass account; '
        & $mk 21 'suspicious_user' '10.42.1.99' 'payments.WireTransfers' 'BATCH COMPLETED' 'DELETE FROM payments.WireTransfers WHERE WireId IN (...)' $false 90 'Suspicious DELETE on financial object' 'DataModification' 'high-risk statement; sensitive object; '
        & $mk 20 'privileged_admin' '10.42.1.71' 'risk.SanctionsScreening' 'PERMISSION CHANGE' 'GRANT SELECT ON risk.SanctionsScreening TO suspicious_user' $true 85 'Permission escalation' 'PermissionChange' 'permission change; '
        # Volume spike / enumeration burst by suspicious_user.
        foreach ($obj in @('core.Customers','core.Accounts','risk.FraudSignals','risk.SanctionsScreening','auditdemo.SensitiveCustomerData','auditdemo.PrivilegedOperations')) {
            for ($z = 0; $z -lt 12; $z++) {
                & $mk 20 'suspicious_user' '10.42.1.99' $obj 'BATCH COMPLETED' "SELECT TOP 20 * FROM $obj" $false 70 'Query volume anomaly' 'BehaviorAnomaly' 'high volume; enumeration; '
            }
        }
        & $mk 15 'fraud_analyst' '10.42.1.60' 'hr.EmployeeAccessProfiles' 'BATCH COMPLETED' 'SELECT * FROM hr.EmployeeAccessProfiles' $false 72 'Out-of-role data access' 'SegregationOfDuties' 'out-of-role for user; '
    }

    Send-LaData -LogType 'SqlAuditPoC' -Records $dayRecords.ToArray()
    $totalPosted += $dayRecords.Count
    if ($offset % 15 -eq 0) { Write-Host ("  seeded through {0:yyyy-MM-dd} ({1} rows so far)" -f $day, $totalPosted) -ForegroundColor DarkGray }
}
Write-Host "Posted $totalPosted synthetic history rows to SqlAuditPoC_CL." -ForegroundColor Green

# --- Seed AI-investigation examples (precomputed) ---------------------------
$aiExamples = @(
    @{ EventTime=(Get-Date).ToUniversalTime().ToString('o'); Detection='DBA after-hours sensitive access'; UserName='dba_user';
       Finding='dba_user read VIP salary/credit/risk fields in auditdemo.SensitiveCustomerData at 22:xx UTC, outside the expected 08-18 window. Privileged access is allowed, but the timing and VIP data target make this unusual for this user.';
       Evidence='UserName=dba_user; ObjectName=auditdemo.SensitiveCustomerData; Statement includes SalaryBand/CreditScore/InternalRiskComment; after-hours; RiskCategory=SensitiveDataAccess';
       Recommendation='Confirm an approved maintenance/task window; compare to peer DBAs; review whether VIP fields were required.' },
    @{ EventTime=(Get-Date).ToUniversalTime().ToString('o'); Detection='Break-glass account used'; UserName='breakglass_admin';
       Finding='breakglass_admin was used to read admin.AccessRequests. Break-glass accounts should only be used during an approved incident.';
       Evidence='UserName=breakglass_admin; ObjectName=admin.AccessRequests; RiskCategory=BreakGlass';
       Recommendation='Verify an approved incident record exists; rotate break-glass credentials after use.' },
    @{ EventTime=(Get-Date).ToUniversalTime().ToString('o'); Detection='Suspicious DELETE on financial object'; UserName='suspicious_user';
       Finding='suspicious_user issued a DELETE against payments.WireTransfers. Destructive statements against money-movement data are high risk.';
       Evidence='UserName=suspicious_user; ObjectName=payments.WireTransfers; Statement includes DELETE; RiskCategory=DataModification';
       Recommendation='Confirm change ticket; validate the rows targeted; review the account entitlements.' }
)
Send-LaData -LogType 'SqlAuditAI' -Records $aiExamples

# --- Write demo output files -------------------------------------------------
$outDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'outputs'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$md = @()
$md += "# Preloaded AI Investigation Examples (demo-ready)"
$md += ""
$md += "_Seeded during deployment by generate-ai-baseline-data.ps1. Regenerate live findings with run-ai-analysis.ps1._"
$md += ""
foreach ($e in $aiExamples) {
    $md += "## $($e.Detection) - $($e.UserName)"
    $md += "**Finding:** $($e.Finding)"
    $md += ""
    $md += "**Evidence:** $($e.Evidence)"
    $md += ""
    $md += "**Recommended action:** $($e.Recommendation)"
    $md += ""
}
$md -join "`n" | Set-Content -Path (Join-Path $outDir 'demo-ai-summary.md') -Encoding UTF8

@(
"# Behavioural Baseline (preloaded)",
"",
"90 days of synthetic history seeded into SqlAuditPoC_CL and unioned by UnifiedSqlAudit:",
"- Days 1-85: normal in-role behaviour (baseline).",
"- Days 86-90: gradual deviations (rising anomaly scores).",
"- Current day: major anomalies (break-glass, DBA after-hours, DELETE, escalation, volume spike).",
"",
"Baselines and trends are derived directly from this history with make-series /",
"series_decompose_anomalies (see kql/anomaly-detections-kql-ml.kql). No waiting required."
) -join "`n" | Set-Content -Path (Join-Path $outDir 'demo-baseline.md') -Encoding UTF8

Write-Host "AI examples + baseline written to outputs/. History is queryable in ~2-5 min (custom-log latency)." -ForegroundColor Green
Write-Host "Validate: SqlAuditPoC_CL | summarize count() by bin(TimeGenerated, 1d) | render columnchart" -ForegroundColor DarkYellow
