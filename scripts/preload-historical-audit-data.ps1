<#
.SYNOPSIS
  Preloads 90 days of historical SQL audit data, behavioural baselines, anomaly
  scores, trend data and AI-investigation examples so the PoC is DEMO-READY the
  moment deployment finishes. Wrapper around generate-ai-baseline-data.ps1.
.DESCRIPTION
  Run automatically by the azd post-provision hook. Safe to run again with -Force.
  The presenter never has to generate baseline data in front of the customer.
.EXAMPLE
  ./scripts/preload-historical-audit-data.ps1
#>
[CmdletBinding()]
param(
    [switch]$Force,
    [int]$Days = 90
)
if ($Force) { & "$PSScriptRoot\generate-ai-baseline-data.ps1" -Days $Days -Force }
else { & "$PSScriptRoot\generate-ai-baseline-data.ps1" -Days $Days }
