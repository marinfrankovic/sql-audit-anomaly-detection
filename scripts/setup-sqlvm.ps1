<#
.SYNOPSIS
  Configures SQL Server on the Azure VM: enables SQL authentication, creates a
  demo sysadmin login, creates PocBankingAuditDbOnVm, then applies schema, users
  and SQL Server Audit (to the Windows Application log).
.DESCRIPTION
  Step 1 runs a bootstrap script ON the VM (Invoke-AzVMRunCommand) to enable mixed
  mode auth and create the DB + admin login (requires local Windows auth).
  Step 2 connects from this machine over the public IP with SQL auth to apply the
  shared schema/users SQL and configure SQL Server Audit.
  Idempotent. Requires the Az PowerShell module and an authenticated Azure context.
.EXAMPLE
  ./scripts/setup-sqlvm.ps1
#>
[CmdletBinding()]
param(
    [string]$VmSaLogin = 'sqlvmsa',
    [string]$VmSaPassword = 'P0c-VmSa!2026Strong',
    [string]$DemoUserPassword = 'P0c-Demo!User2026',
    [string]$VmDatabase = 'PocBankingAuditDbOnVm'
)

. "$PSScriptRoot\_common.ps1"

if (-not (Get-Module -ListAvailable -Name Az.Compute)) {
    Write-Host "Installing Az.Compute module..." -ForegroundColor Yellow
    Install-Module Az.Compute -Scope CurrentUser -Force -AllowClobber
}
Import-Module Az.Compute -ErrorAction Stop

$env = Get-PocEnv
$rg     = $env['AZURE_RESOURCE_GROUP']
$vmName = $env['VM_NAME']
$vmIp   = $env['VM_PUBLIC_IP']
if (-not $vmName) { throw "VM_NAME not found. Run 'azd up' first." }

# Ensure the Az PowerShell module is authenticated (reuses the Azure CLI login).
Ensure-PocAzContext -Subscription $env['AZURE_SUBSCRIPTION_ID']

Write-Host "SQL VM setup -> $vmName ($vmIp)" -ForegroundColor Green

# --- Step 1: bootstrap SQL auth (mixed mode) + DB + admin login on the VM ----
Write-Host "  [1/4] Bootstrapping SQL auth + database on the VM (this can take ~1-2 min)..." -ForegroundColor Cyan
Initialize-PocVmSqlServer -PocEnv $env -VmSaLogin $VmSaLogin -VmSaPassword $VmSaPassword -VmDatabase $VmDatabase
Write-Host "  Bootstrap complete." -ForegroundColor Green

# --- Step 2: apply schema/users/audit over SQL auth via public IP -----------
# Temporarily open SQL 1433 on the VM; always close it again in the finally.
$serverInstance = "$vmIp,1433"
Ensure-SqlServerModule
Open-PocVmSqlPort -PocEnv $env

try {
    Write-Host "  [2/4] Creating schemas and tables on $VmDatabase..." -ForegroundColor Cyan
    Invoke-Sqlcmd -ServerInstance $serverInstance -Database $VmDatabase -Username $VmSaLogin -Password $VmSaPassword `
        -InputFile "$PSScriptRoot\sql\schema.sql" -Encrypt Optional -TrustServerCertificate -QueryTimeout 300 -ErrorAction Stop | Out-Null

    Write-Host "  [3/4] Creating demo logins/users and permissions..." -ForegroundColor Cyan
    Invoke-Sqlcmd -ServerInstance $serverInstance -Database $VmDatabase -Username $VmSaLogin -Password $VmSaPassword `
        -InputFile "$PSScriptRoot\sql\users.sql" -Encrypt Optional -TrustServerCertificate -QueryTimeout 300 -ErrorAction Stop `
        -Variable @("IsAzureSql=0", "DemoUserPassword=$DemoUserPassword") | Out-Null

    Write-Host "  [4/4] Configuring SQL Server Audit -> Windows Application log..." -ForegroundColor Cyan
    Invoke-Sqlcmd -ServerInstance $serverInstance -Database $VmDatabase -Username $VmSaLogin -Password $VmSaPassword `
        -InputFile "$PSScriptRoot\sql\vm-audit.sql" -Encrypt Optional -TrustServerCertificate -QueryTimeout 300 -ErrorAction Stop `
        -Variable @("DbName=$VmDatabase") | Out-Null
}
finally {
    Close-PocVmSqlPort -PocEnv $env
}

Write-Host "SQL VM configuration complete. Audit records flow: SQL Audit -> Application log -> Azure Monitor Agent -> Log Analytics (Event table)." -ForegroundColor Green
Write-Host "Next: ./scripts/create-mock-data.ps1" -ForegroundColor Yellow
