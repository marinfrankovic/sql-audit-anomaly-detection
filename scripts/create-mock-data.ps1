<#
.SYNOPSIS
  Populates synthetic banking mock data into Azure SQL (large volume) and/or the VM (small volume).
.DESCRIPTION
  Idempotent - the generator only inserts when core.Customers is empty.
  ALL DATA IS SYNTHETIC. No real personal data.
.PARAMETER Target
  Azure | Vm | Both (default Both).
.EXAMPLE
  ./scripts/create-mock-data.ps1 -Target Both
#>
[CmdletBinding()]
param(
    [ValidateSet('Azure','Vm','Both')][string]$Target = 'Both',
    [string]$VmSaLogin = 'sqlvmsa',
    [string]$VmSaPassword = 'P0c-VmSa!2026Strong',
    [string]$VmDatabase = 'PocBankingAuditDbOnVm'
)

. "$PSScriptRoot\_common.ps1"
Ensure-SqlServerModule
$env = Get-PocEnv

# Large volumes for Azure SQL (per spec).
$azureVars = @(
    "CustomerCount=2500","AccountCount=5000","TransactionCount=50000",
    "PaymentInstructionCount=1000","WireTransferCount=500","RiskScoreCount=2500",
    "SanctionsCount=200","FraudSignalCount=1500","AccessProfileCount=250","AccessRequestCount=500"
)
# Smaller volumes for the VM (per spec).
$vmVars = @(
    "CustomerCount=500","AccountCount=1000","TransactionCount=10000",
    "PaymentInstructionCount=300","WireTransferCount=200","RiskScoreCount=500",
    "SanctionsCount=100","FraudSignalCount=300","AccessProfileCount=100","AccessRequestCount=200"
)

if ($Target -in @('Azure','Both')) {
    $server = $env['SQL_SERVER_FQDN']; $database = $env['SQL_DATABASE_NAME']
    $login  = $env['SQL_ADMIN_LOGIN']; $vault = $env['KEY_VAULT_NAME']
    if (-not $server) { Write-Warning "Azure SQL not deployed - skipping Azure mock data (VM carries the persona demo)." }
    else {
        $password = Get-PocSecret -VaultName $vault -SecretName 'sql-admin-password'
        Write-Host "Generating mock data in Azure SQL ($database)... this may take a couple of minutes." -ForegroundColor Cyan
        Invoke-Sqlcmd -ServerInstance $server -Database $database -Username $login -Password $password `
            -InputFile "$PSScriptRoot\sql\mockdata.sql" -Encrypt Mandatory -QueryTimeout 1200 -ErrorAction Stop `
            -Variable $azureVars -Verbose | Out-Null
        Write-Host "  Azure SQL mock data ready." -ForegroundColor Green
    }
}

if ($Target -in @('Vm','Both')) {
    $vmIp = $env['VM_PUBLIC_IP']
    if (-not $vmIp) { Write-Warning "VM_PUBLIC_IP not found - skipping VM. Run setup-sqlvm.ps1 first."; }
    else {
        Open-PocVmSqlPort -PocEnv $env
        try {
            Write-Host "Generating mock data on the SQL VM ($VmDatabase)..." -ForegroundColor Cyan
            Invoke-Sqlcmd -ServerInstance "$vmIp,1433" -Database $VmDatabase -Username $VmSaLogin -Password $VmSaPassword `
                -InputFile "$PSScriptRoot\sql\mockdata.sql" -Encrypt Optional -TrustServerCertificate -QueryTimeout 1200 -ErrorAction Stop `
                -Variable $vmVars -Verbose | Out-Null
            Write-Host "  VM mock data ready." -ForegroundColor Green
        }
        finally {
            Close-PocVmSqlPort -PocEnv $env
        }
    }
}

Write-Host "Mock data generation complete." -ForegroundColor Green
