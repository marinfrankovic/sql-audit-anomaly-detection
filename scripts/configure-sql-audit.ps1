<#
.SYNOPSIS
  Configures / verifies SQL auditing for the PoC.
.DESCRIPTION
  - Azure SQL: server-level auditing to Log Analytics is provisioned by Bicep. This
    script verifies the setting and (optionally) can be extended for DB-level audit.
  - VM: applies sql/vm-audit.sql to create SQL Server Audit -> Windows Application log.
  Idempotent.
.PARAMETER Target
  Azure | Vm | Both (default Both).
.EXAMPLE
  ./scripts/configure-sql-audit.ps1 -Target Both
#>
[CmdletBinding()]
param(
    [ValidateSet('Azure','Vm','Both')][string]$Target = 'Both',
    [string]$VmSaLogin = 'sqlvmsa',
    [string]$VmSaPassword = 'P0c-VmSa!2026Strong',
    [string]$VmDatabase = 'PocBankingAuditDbOnVm'
)

. "$PSScriptRoot\_common.ps1"
$env = Get-PocEnv

if ($Target -in @('Azure','Both')) {
    $server = $env['SQL_SERVER_NAME']; $rg = $env['AZURE_RESOURCE_GROUP']
    if ($server -and $rg) {
        Write-Host "Verifying Azure SQL server auditing state..." -ForegroundColor Cyan
        $state = az sql server audit-policy show --resource-group $rg --name $server --query 'state' -o tsv 2>$null
        Write-Host "  Azure SQL auditing state: $state (expected: Enabled)" -ForegroundColor Green
        Write-Host "  Auditing targets Log Analytics (isAzureMonitorTargetEnabled=true) via Bicep." -ForegroundColor Gray
    } else {
        Write-Warning "Azure SQL server/resource group not found in env - skipping verification."
    }
}

if ($Target -in @('Vm','Both')) {
    $vmIp = $env['VM_PUBLIC_IP']
    if (-not $vmIp) { Write-Warning "VM_PUBLIC_IP not found - skipping VM audit configuration." }
    else {
        Ensure-SqlServerModule
        Open-PocVmSqlPort -PocEnv $env
        try {
            Write-Host "Configuring SQL Server Audit on the VM ($VmDatabase)..." -ForegroundColor Cyan
            Invoke-Sqlcmd -ServerInstance "$vmIp,1433" -Database $VmDatabase -Username $VmSaLogin -Password $VmSaPassword `
                -InputFile "$PSScriptRoot\sql\vm-audit.sql" -Encrypt Optional -TrustServerCertificate -QueryTimeout 300 -ErrorAction Stop `
                -Variable @("DbName=$VmDatabase") | Out-Null
            Write-Host "  VM SQL Server Audit (SqlAudit_PoC) is ON, writing to the Application log." -ForegroundColor Green
        }
        finally {
            Close-PocVmSqlPort -PocEnv $env
        }
    }
}

Write-Host "SQL auditing configuration/verification complete." -ForegroundColor Green
