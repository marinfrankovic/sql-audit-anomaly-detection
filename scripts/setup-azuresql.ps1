<#
.SYNOPSIS
  Configures the Azure SQL database (PocBankingAuditDb): schemas, tables and demo users.
.DESCRIPTION
  Idempotent. Reads connection details from the azd environment and the SQL admin
  password from Key Vault. Run after `azd up`.
.EXAMPLE
  ./scripts/setup-azuresql.ps1
#>
[CmdletBinding()]
param(
    [string]$DemoUserPassword = 'P0c-Demo!User2026'
)

. "$PSScriptRoot\_common.ps1"

$env = Get-PocEnv
$server   = $env['SQL_SERVER_FQDN']
$database = $env['SQL_DATABASE_NAME']
$login    = $env['SQL_ADMIN_LOGIN']
$vault    = $env['KEY_VAULT_NAME']

if (-not $server) { Write-Warning "Azure SQL not deployed (enableAzureSql=false) - skipping. The VM SQL Server carries the persona demo."; return }

Write-Host "Azure SQL setup -> $server / $database" -ForegroundColor Green
$password = Get-PocSecret -VaultName $vault -SecretName 'sql-admin-password'
Ensure-SqlServerModule

Write-Host "  [1/2] Creating schemas and tables..." -ForegroundColor Cyan
Invoke-Sqlcmd -ServerInstance $server -Database $database -Username $login -Password $password `
    -InputFile "$PSScriptRoot\sql\schema.sql" -Encrypt Mandatory -QueryTimeout 300 -ErrorAction Stop | Out-Null

Write-Host "  [2/2] Creating demo users and permissions (contained users)..." -ForegroundColor Cyan
Invoke-Sqlcmd -ServerInstance $server -Database $database -Username $login -Password $password `
    -InputFile "$PSScriptRoot\sql\users.sql" -Encrypt Mandatory -QueryTimeout 300 -ErrorAction Stop `
    -Variable @("IsAzureSql=1", "DemoUserPassword=$DemoUserPassword") | Out-Null

Write-Host "Azure SQL configuration complete." -ForegroundColor Green
Write-Host "Server-level auditing to Log Analytics was enabled by the Bicep deployment." -ForegroundColor Gray
Write-Host "Next: ./scripts/create-mock-data.ps1" -ForegroundColor Yellow
