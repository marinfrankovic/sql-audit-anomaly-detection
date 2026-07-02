<#
.SYNOPSIS
  End-to-end orchestrator for the SQL Audit PoC demo.
.DESCRIPTION
  Convenience wrapper that runs the full post-deployment pipeline or individual stages.
  Idempotent - safe to re-run.
.PARAMETER Setup
  Run schema/users/audit setup and mock data for both databases.
.PARAMETER Normal
  Generate normal baseline activity.
.PARAMETER Wow
  Generate the WOW detection scenarios.
.PARAMETER All
  Setup + Normal + Wow (default if no switch is provided).
.PARAMETER Target
  Azure | Vm | Both (default Both for setup; Azure for activity).
.EXAMPLE
  ./scripts/run-poc-scenarios.ps1 -All
.EXAMPLE
  ./scripts/run-poc-scenarios.ps1 -Wow -Target Azure
#>
[CmdletBinding()]
param(
    [switch]$Setup,
    [switch]$Normal,
    [switch]$Wow,
    [switch]$All,
    [ValidateSet('Azure','Vm','Both')][string]$Target = 'Both'
)

. "$PSScriptRoot\_common.ps1"

if (-not ($Setup -or $Normal -or $Wow)) { $All = $true }

$sw = [System.Diagnostics.Stopwatch]::StartNew()

if ($Setup -or $All) {
    Write-Host "`n=== STAGE 0: PRELOAD 90-DAY HISTORY (demo-ready) ===" -ForegroundColor Green
    & "$PSScriptRoot\preload-historical-audit-data.ps1"
    Write-Host "`n=== STAGE 1: SETUP ===" -ForegroundColor Green
    if ($Target -in @('Azure','Both')) { & "$PSScriptRoot\setup-azuresql.ps1" }
    if ($Target -in @('Vm','Both'))    { & "$PSScriptRoot\setup-sqlvm.ps1" }
    Write-Host "`n=== STAGE 2: MOCK DATA ===" -ForegroundColor Green
    & "$PSScriptRoot\create-mock-data.ps1" -Target $Target
}

# Activity is generated against Azure by default (VM optional).
$activityTarget = if ($Target -eq 'Vm') { 'Vm' } elseif ($Target -eq 'Both') { 'Both' } else { 'Azure' }

if ($Normal -or $All) {
    Write-Host "`n=== STAGE 3: NORMAL ACTIVITY ===" -ForegroundColor Green
    & "$PSScriptRoot\generate-normal-activity.ps1" -Target $activityTarget
}

if ($Wow -or $All) {
    Write-Host "`n=== STAGE 4: WOW DETECTIONS ===" -ForegroundColor Green
    & "$PSScriptRoot\generate-wow-detections.ps1" -Target $activityTarget
}

if ($All) {
    Write-Host "`n=== STAGE 5: AI ANALYSIS ===" -ForegroundColor Green
    & "$PSScriptRoot\run-ai-analysis.ps1"
}

$sw.Stop()
Write-Host "`nPoC scenario run complete in $([math]::Round($sw.Elapsed.TotalMinutes,1)) min." -ForegroundColor Green
Write-Host "Open the Azure Workbook and refresh. See docs/demo-walkthrough.md for the talk track." -ForegroundColor Yellow
