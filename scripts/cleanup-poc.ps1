<#
.SYNOPSIS
  Cleans up the SQL Audit PoC.
.DESCRIPTION
  By default resets only the demo data (DemoEvents / re-armable state) so the demo
  can be re-run. Use -DeleteAll to tear down ALL Azure resources with `azd down`.
.PARAMETER DeleteAll
  Run `azd down --purge --force` to delete the resource group and all resources.
.PARAMETER ResetDemoData
  Truncate auditdemo.DemoEvents markers on both databases (default action).
.EXAMPLE
  ./scripts/cleanup-poc.ps1                 # reset demo markers only
.EXAMPLE
  ./scripts/cleanup-poc.ps1 -DeleteAll      # delete everything in Azure
#>
[CmdletBinding()]
param(
    [switch]$DeleteAll,
    [switch]$ResetDemoData,
    [string]$DemoUserPassword = 'P0c-Demo!User2026',
    [string]$VmSaLogin = 'sqlvmsa',
    [string]$VmSaPassword = 'P0c-VmSa!2026Strong',
    [string]$VmDatabase = 'PocBankingAuditDbOnVm'
)

. "$PSScriptRoot\_common.ps1"

if ($DeleteAll) {
    Write-Host "This will DELETE all Azure resources for this PoC (azd down --purge)." -ForegroundColor Red
    $confirm = Read-Host "Type 'DELETE' to confirm"
    if ($confirm -ne 'DELETE') { Write-Host "Aborted." -ForegroundColor Yellow; return }
    azd down --purge --force
    Write-Host "Teardown requested via azd down." -ForegroundColor Green
    return
}

# Default: reset demo markers so scenarios can be re-run cleanly.
$ResetDemoData = $true
Ensure-SqlServerModule
$env = Get-PocEnv

if ($env['SQL_SERVER_FQDN']) {
    $password = Get-PocSecret -VaultName $env['KEY_VAULT_NAME'] -SecretName 'sql-admin-password'
    Write-Host "Resetting demo markers in Azure SQL..." -ForegroundColor Cyan
    Invoke-Sqlcmd -ServerInstance $env['SQL_SERVER_FQDN'] -Database $env['SQL_DATABASE_NAME'] `
        -Username $env['SQL_ADMIN_LOGIN'] -Password $password -Encrypt Mandatory -ErrorAction Stop `
        -Query "IF OBJECT_ID('auditdemo.DemoEvents') IS NOT NULL TRUNCATE TABLE auditdemo.DemoEvents;" | Out-Null
}

if ($env['VM_PUBLIC_IP']) {
    Write-Host "Resetting demo markers on the SQL VM..." -ForegroundColor Cyan
    Open-PocVmSqlPort -PocEnv $env
    try {
        Invoke-Sqlcmd -ServerInstance "$($env['VM_PUBLIC_IP']),1433" -Database $VmDatabase `
            -Username $VmSaLogin -Password $VmSaPassword -Encrypt Optional -TrustServerCertificate -ErrorAction Stop `
            -Query "IF OBJECT_ID('auditdemo.DemoEvents') IS NOT NULL TRUNCATE TABLE auditdemo.DemoEvents;" | Out-Null
    } catch { Write-Warning "VM reset skipped: $($_.Exception.Message.Split([Environment]::NewLine)[0])" }
    finally { Close-PocVmSqlPort -PocEnv $env }
}

Write-Host "Demo markers reset. To delete all Azure resources run: ./scripts/cleanup-poc.ps1 -DeleteAll  (or 'azd down --purge')." -ForegroundColor Green
