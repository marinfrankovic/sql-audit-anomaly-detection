<#
.SYNOPSIS
  Creates (or updates) the UnifiedSqlAudit saved function in the Log Analytics
  workspace. UnifiedSqlAudit is a normalised, single-schema view over the preloaded
  history table SqlAuditPoC_CL, exposing a friendly column set (EventTime, UserName,
  ObjectName, Action, RiskCategory, DetectionName, AnomalyScore, ...).
.DESCRIPTION
  History rows carry the true business event time in the EventTime_t datetime column
  (the Data Collector API clamps a back-dated TimeGenerated, so we bin by EventTime_t
  instead). This function filters to rows that have EventTime_t so any earlier,
  non-back-dated seed rows are excluded. Idempotent.
.EXAMPLE
  ./scripts/create-unified-function.ps1
#>
[CmdletBinding()]
param()

. "$PSScriptRoot\_common.ps1"
$env = Get-PocEnv
$sub = $env['AZURE_SUBSCRIPTION_ID']
$rg  = $env['AZURE_RESOURCE_GROUP']
$ws  = $env['LOG_ANALYTICS_NAME']
if (-not $rg -or -not $ws -or -not $sub) { throw "AZURE_SUBSCRIPTION_ID / AZURE_RESOURCE_GROUP / LOG_ANALYTICS_NAME not found. Run 'azd up' first." }

$query = @'
SqlAuditPoC_CL
| where isnotempty(EventTime_t)
| project EventTime = EventTime_t,
          SourceType = SourceType_s,
          ServerName = ServerName_s,
          DatabaseName = DatabaseName_s,
          UserName = UserName_s,
          ClientIp = ClientIp_s,
          ApplicationName = ApplicationName_s,
          Action = Action_s,
          ObjectName = ObjectName_s,
          SchemaName = SchemaName_s,
          Statement = Statement_s,
          RiskCategory = RiskCategory_s,
          DetectionName = DetectionName_s,
          IsPrivilegedUser = IsPrivilegedUser_b,
          IsSensitiveObject = IsSensitiveObject_b,
          IsAfterHours = IsAfterHours_b,
          AnomalyScore = toint(AnomalyScore_d),
          BehaviorExplanation = BehaviorExplanation_s
'@

Write-Host "Creating/updating UnifiedSqlAudit function in $ws..." -ForegroundColor Cyan

# Use the ARM REST API (az rest) with a JSON body so the multi-line KQL and the
# function alias are set reliably. Passing a multi-line --saved-query on the CLI
# truncates the query at the first newline on Windows PowerShell.
$body = @{
    properties = @{
        category      = 'SQL Audit PoC'
        displayName   = 'UnifiedSqlAudit'
        query         = $query
        functionAlias = 'UnifiedSqlAudit'
        version       = 2
    }
} | ConvertTo-Json -Depth 5

$tmp = New-TemporaryFile
try {
    Set-Content -Path $tmp.FullName -Value $body -Encoding utf8 -NoNewline
    $url = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.OperationalInsights/workspaces/$ws/savedSearches/UnifiedSqlAudit?api-version=2020-08-01"
    az rest --method put --url $url --headers "Content-Type=application/json" --body "@$($tmp.FullName)" -o none
    if ($LASTEXITCODE -ne 0) { throw "Failed to create UnifiedSqlAudit function (az exit $LASTEXITCODE)." }
} finally {
    Remove-Item $tmp.FullName -Force -ErrorAction SilentlyContinue
}

Write-Host "UnifiedSqlAudit function is ready (use it like a table: 'UnifiedSqlAudit | take 10')." -ForegroundColor Green
