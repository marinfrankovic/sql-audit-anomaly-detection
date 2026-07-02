<#
.SYNOPSIS
  Creates (or re-applies) the demo SQL users/logins and permissions on Azure SQL and/or the VM.
.DESCRIPTION
  Idempotent. Wraps sql/users.sql. Azure SQL uses contained users; the VM uses logins + users.
.PARAMETER Target
  Azure | Vm | Both (default Both).
.EXAMPLE
  ./scripts/create-sql-users.ps1 -Target Both
#>
[CmdletBinding()]
param(
    [ValidateSet('Azure','Vm','Both')][string]$Target = 'Both',
    [string]$DemoUserPassword = 'P0c-Demo!User2026',
    [string]$VmSaLogin = 'sqlvmsa',
    [string]$VmSaPassword = 'P0c-VmSa!2026Strong',
    [string]$VmDatabase = 'PocBankingAuditDbOnVm'
)

. "$PSScriptRoot\_common.ps1"
Ensure-SqlServerModule
$env = Get-PocEnv

if ($Target -in @('Azure','Both')) {
    $server = $env['SQL_SERVER_FQDN']; $database = $env['SQL_DATABASE_NAME']
    $login  = $env['SQL_ADMIN_LOGIN']; $vault = $env['KEY_VAULT_NAME']
    if (-not $server) { throw "SQL_SERVER_FQDN not found. Run 'azd up' first." }
    $password = Get-PocSecret -VaultName $vault -SecretName 'sql-admin-password'
    Write-Host "Applying demo users to Azure SQL ($database)..." -ForegroundColor Cyan
    Invoke-Sqlcmd -ServerInstance $server -Database $database -Username $login -Password $password `
        -InputFile "$PSScriptRoot\sql\users.sql" -Encrypt Mandatory -QueryTimeout 300 -ErrorAction Stop `
        -Variable @("IsAzureSql=1", "DemoUserPassword=$DemoUserPassword") | Out-Null
    Write-Host "  Azure SQL users ready." -ForegroundColor Green
}

if ($Target -in @('Vm','Both')) {
    $vmIp = $env['VM_PUBLIC_IP']
    if (-not $vmIp) { Write-Warning "VM_PUBLIC_IP not found - skipping VM." }
    else {
        Write-Host "Applying demo users to the SQL VM ($VmDatabase)..." -ForegroundColor Cyan
        Invoke-Sqlcmd -ServerInstance "$vmIp,1433" -Database $VmDatabase -Username $VmSaLogin -Password $VmSaPassword `
            -InputFile "$PSScriptRoot\sql\users.sql" -Encrypt Optional -TrustServerCertificate -QueryTimeout 300 -ErrorAction Stop `
            -Variable @("IsAzureSql=0", "DemoUserPassword=$DemoUserPassword") | Out-Null
        Write-Host "  VM users ready." -ForegroundColor Green
    }
}

Write-Host "Demo users and permissions ensured." -ForegroundColor Green
