<#
.SYNOPSIS
  Runs the read-only AI Analyst over the latest SQL audit anomalies and saves a
  customer-friendly summary to outputs/demo-ai-summary.md.
.DESCRIPTION
  1) Queries Log Analytics for the latest anomalies (preloaded history + live).
  2) Calls the AI Analyst Function App (Azure OpenAI, read-only, grounded).
  3) Prints and saves the summary. Falls back to the preloaded examples if the AI
     layer is not deployed (enableAzureOpenAI=false / deployAiAnalystFunction=false).
.EXAMPLE
  ./scripts/run-ai-analysis.ps1
#>
[CmdletBinding()]
param(
    [int]$TopN = 20
)

. "$PSScriptRoot\_common.ps1"
$env = Get-PocEnv
$customerId = $env['LOG_ANALYTICS_CUSTOMER_ID']
$funcUrl = $env['AI_ANALYST_FUNCTION_URL']
$funcName = $env['AI_ANALYST_FUNCTION_NAME']
$rg = $env['AZURE_RESOURCE_GROUP']

$outDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'outputs'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$outFile = Join-Path $outDir 'demo-ai-summary.md'

# ---- 1) Collect latest anomalies (preloaded history + live audit) -----------
$kql = @"
let priv = dynamic(['dba_user','privileged_admin','breakglass_admin']);
let sensitive = dynamic(['SensitiveCustomerData','FraudSignals','WireTransfers','SanctionsScreening','CustomerRiskScores','EmployeeAccessProfiles','AccessRequests']);
let hist = SqlAuditPoC_CL | where TimeGenerated > ago(2d) | extend UserName=UserName_s, ObjectName=ObjectName_s, Statement=Statement_s, DetectionName=DetectionName_s, RiskCategory=RiskCategory_s, ClientIp=ClientIp_s, DatabaseName=DatabaseName_s, AnomalyScore=toint(AnomalyScore_d) | where DetectionName != 'None';
let live = SQLSecurityAuditEvents | where TimeGenerated > ago(1d) | extend U=tolower(ServerPrincipalName)
  | where U=='breakglass_admin' or ObjectName has 'SensitiveCustomerData' or Statement matches regex @'(?i)\b(DELETE|GRANT|ALTER\s+ROLE|ADD\s+MEMBER)\b'
  | extend UserName=ServerPrincipalName, DatabaseName=DatabaseName, ObjectName=ObjectName, ClientIp=ClientIp, Statement=Statement,
           DetectionName=case(U=='breakglass_admin','Break-glass account used', ObjectName has 'SensitiveCustomerData','Sensitive object access','High-risk statement'),
           RiskCategory=case(U=='breakglass_admin','BreakGlass', ObjectName has 'SensitiveCustomerData','SensitiveDataAccess','HighRiskStatement'), AnomalyScore=80;
union isfuzzy=true hist, live
| project EventTime=TimeGenerated, UserName, DatabaseName, ObjectName, ClientIp, Statement=substring(Statement,0,300), RiskCategory, DetectionName, AnomalyScore
| order by AnomalyScore desc, EventTime desc
| take $TopN
"@

Write-Host "Collecting latest anomalies from Log Analytics..." -ForegroundColor Cyan
$rows = @()
try {
    $json = az monitor log-analytics query --workspace $customerId --analytics-query $kql -o json 2>$null
    if ($json) { $rows = $json | ConvertFrom-Json }
} catch { Write-Warning "Log Analytics query failed: $($_.Exception.Message.Split([Environment]::NewLine)[0])" }
Write-Host "  $($rows.Count) anomaly rows collected." -ForegroundColor Gray

# ---- 2) Call the AI Analyst API (if deployed) ------------------------------
$aiConfigured = ($funcUrl -and $env['ENABLE_AZURE_OPENAI'] -ne 'false')
if ($aiConfigured -and $rows.Count -gt 0) {
    try {
        $key = az functionapp keys list -g $rg -n $funcName --query 'functionKeys.default' -o tsv 2>$null
        if (-not $key) { $key = az functionapp keys list -g $rg -n $funcName --query 'masterKey' -o tsv 2>$null }
        $body = @{ evidence = $rows } | ConvertTo-Json -Depth 8
        $uri = "$funcUrl/api/analyze/daily-summary?code=$key"
        Write-Host "Calling AI Analyst: $funcUrl/api/analyze/daily-summary" -ForegroundColor Cyan
        $resp = Invoke-RestMethod -Method Post -Uri $uri -ContentType 'application/json' -Body $body -TimeoutSec 120
        $summary = $resp.summary
        $md = "# AI-Assisted SQL Risk Summary (live)`n`n_Generated $(Get-Date -Format s) by run-ai-analysis.ps1 via the read-only AI Analyst._`n`n$summary`n"
        $md | Set-Content -Path $outFile -Encoding UTF8
        Write-Host "`n===== AI SUMMARY =====`n" -ForegroundColor Green
        Write-Host $summary
        Write-Host "`nSaved to $outFile" -ForegroundColor Green
        return
    } catch {
        Write-Warning "AI Analyst call failed: $($_.Exception.Message.Split([Environment]::NewLine)[0])"
    }
}

# ---- 3) Fallback: preloaded examples ---------------------------------------
Write-Host "AI Analyst not available (or disabled) - using preloaded examples." -ForegroundColor Yellow
if (Test-Path $outFile) {
    Write-Host "See existing $outFile (preloaded during deployment)." -ForegroundColor Gray
    Get-Content $outFile | Select-Object -First 40 | ForEach-Object { Write-Host $_ }
} else {
    Write-Host "Run ./scripts/preload-historical-audit-data.ps1 to seed AI examples." -ForegroundColor Gray
}
