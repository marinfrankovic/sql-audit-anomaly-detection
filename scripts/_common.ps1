<#
.SYNOPSIS
  Shared helpers for the SQL Audit PoC scripts: loads azd environment outputs,
  resolves secrets from Key Vault, and provides a safe Invoke-Sqlcmd wrapper.

  Dot-source this file from the other scripts:  . "$PSScriptRoot\_common.ps1"
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PocEnv {
    <#
      Loads outputs from the current azd environment into a hashtable.
      Falls back to environment variables if azd is not available.
    #>
    [CmdletBinding()]
    param()

    $values = @{}
    $azd = Get-Command azd -ErrorAction SilentlyContinue
    if ($azd) {
        try {
            $lines = azd env get-values 2>$null
            foreach ($line in $lines) {
                if ($line -match '^\s*([A-Z0-9_]+)="?(.*?)"?\s*$') {
                    $values[$Matches[1]] = $Matches[2]
                }
            }
        } catch {
            Write-Warning "Could not read azd env values: $($_.Exception.Message)"
        }
    }

    # Allow env-var overrides (useful when running outside azd).
    foreach ($k in @(
        'SQL_SERVER_FQDN','SQL_DATABASE_NAME','SQL_ADMIN_LOGIN','SQL_SERVER_NAME',
        'VM_NAME','VM_PUBLIC_IP','VM_SQL_DATABASE_NAME','KEY_VAULT_NAME',
        'AZURE_RESOURCE_GROUP','LOG_ANALYTICS_NAME','AZURE_LOCATION')) {
        $ev = [System.Environment]::GetEnvironmentVariable($k)
        if ($ev) { $values[$k] = $ev }
    }

    return $values
}

function Get-PocSecret {
    <# Reads a secret from the PoC Key Vault. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$VaultName,
        [Parameter(Mandatory)][string]$SecretName
    )
    $val = az keyvault secret show --vault-name $VaultName --name $SecretName --query value -o tsv 2>$null
    if (-not $val) { throw "Could not read secret '$SecretName' from vault '$VaultName'. Ensure you have 'Key Vault Secrets User' role." }
    return $val
}

function Ensure-SqlServerModule {
    <# Ensures the SqlServer PowerShell module (Invoke-Sqlcmd) is available. #>
    if (-not (Get-Module -ListAvailable -Name SqlServer)) {
        Write-Host "Installing SqlServer PowerShell module for the current user..." -ForegroundColor Yellow
        Install-Module -Name SqlServer -Scope CurrentUser -Force -AllowClobber
    }
    Import-Module SqlServer -ErrorAction Stop
}

function Ensure-PocAzContext {
    <#
      Ensures the Az PowerShell module has an authenticated context.
      Reuses the existing Azure CLI login (no second sign-in) by bridging its
      ARM access token into Az. Falls back to interactive Connect-AzAccount.
    #>
    [CmdletBinding()]
    param(
        [string]$Subscription,
        # Skip the reuse check and always re-bridge a fresh CLI token. Used by
        # retry logic after an 'ExpiredAuthenticationToken' failure.
        [switch]$Force
    )

    if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
        Write-Host "Installing Az.Accounts module..." -ForegroundColor Yellow
        Install-Module Az.Accounts -Scope CurrentUser -Force -AllowClobber
    }
    Import-Module Az.Accounts -ErrorAction Stop

    $ctx = $null
    try { $ctx = Get-AzContext } catch { $ctx = $null }
    # Reuse the current context while the token we bridged is still comfortably
    # valid. We track the mint time ourselves (a bridged CLI access token is not
    # refreshable, and probing it with Get-AzAccessToken emits noisy warnings and
    # cannot renew it). Re-bridging a fresh CLI token is cheap, so we cap reuse
    # at ~45 min - well within an ARM token's ~60-90 min lifetime.
    $validUntil = if (Test-Path variable:global:PocAzTokenValidUntil) { $global:PocAzTokenValidUntil } else { $null }
    if (-not $Force -and $ctx -and $ctx.Subscription -and $validUntil -and $validUntil -gt (Get-Date).ToUniversalTime()) {
        if ($Subscription -and $ctx.Subscription.Id -ne $Subscription) {
            try { Set-AzContext -Subscription $Subscription -ErrorAction Stop | Out-Null } catch { }
        }
        return
    }

    # Bridge the existing Azure CLI login so the user does not sign in twice.
    $acct = $null
    try { $acct = az account show -o json 2>$null | ConvertFrom-Json } catch { $acct = $null }
    if ($acct) {
        if (-not $Subscription) { $Subscription = $acct.id }
        $tenant = $acct.tenantId
        $upn    = $acct.user.name
        $tok    = az account get-access-token --resource https://management.azure.com --query accessToken -o tsv 2>$null
        if ($tok) {
            # Az.Accounts >= 5 expects -AccessToken as SecureString; older versions expect a string.
            try {
                $secTok = ConvertTo-SecureString $tok -AsPlainText -Force
                Connect-AzAccount -AccessToken $secTok -AccountId $upn -Tenant $tenant -Subscription $Subscription -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
                $global:PocAzTokenValidUntil = (Get-Date).ToUniversalTime().AddMinutes(45)
                Write-Host "Az context bridged from Azure CLI login ($upn)." -ForegroundColor DarkGray
                return
            } catch {
                try {
                    Connect-AzAccount -AccessToken $tok -AccountId $upn -Tenant $tenant -Subscription $Subscription -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
                    $global:PocAzTokenValidUntil = (Get-Date).ToUniversalTime().AddMinutes(45)
                    Write-Host "Az context bridged from Azure CLI login ($upn)." -ForegroundColor DarkGray
                    return
                } catch {
                    Write-Warning "Could not bridge Azure CLI token into Az: $($_.Exception.Message). Falling back to interactive sign-in."
                }
            }
        }
    }

    Write-Host "Signing in to Azure (Az PowerShell)..." -ForegroundColor Yellow
    if ($Subscription) { Connect-AzAccount -Subscription $Subscription -ErrorAction Stop | Out-Null }
    else { Connect-AzAccount -ErrorAction Stop | Out-Null }
    $global:PocAzTokenValidUntil = (Get-Date).ToUniversalTime().AddMinutes(45)
}

function Invoke-PocVMRunCommand {
    <#
      Wrapper around Invoke-AzVMRunCommand that survives token expiry during
      long-running executions. On an 'ExpiredAuthenticationToken' / 401 failure
      it force-refreshes the Az context (re-bridging a fresh Azure CLI token)
      and retries, so a demo run never dies mid-command because the ARM token
      aged out. Returns the raw Invoke-AzVMRunCommand result object.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$VMName,
        [string]$CommandId = 'RunPowerShellScript',
        [Parameter(Mandatory)][string]$ScriptString,
        [string]$Subscription,
        [int]$MaxAttempts = 3
    )

    # Invoke-AzVMRunCommand ships in Az.Compute - ensure it is available wherever
    # this wrapper is called (not every script imports it explicitly).
    if (-not (Get-Command Invoke-AzVMRunCommand -ErrorAction SilentlyContinue)) {
        if (-not (Get-Module -ListAvailable -Name Az.Compute)) {
            Write-Host "Installing Az.Compute module..." -ForegroundColor Yellow
            Install-Module Az.Compute -Scope CurrentUser -Force -AllowClobber
        }
        Import-Module Az.Compute -ErrorAction Stop
    }

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        # Proactively ensure a valid token before each attempt (re-bridges when
        # the existing one is expired or within 15 min of expiry).
        Ensure-PocAzContext -Subscription $Subscription -Force:($attempt -gt 1)
        try {
            return Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $VMName `
                -CommandId $CommandId -ScriptString $ScriptString -ErrorAction Stop
        } catch {
            $msg = $_.Exception.Message
            $isAuth = $msg -match 'ExpiredAuthenticationToken' -or $msg -match 'access token expiry' -or `
                      $msg -match '\b401\b' -or $msg -match 'Unauthorized'
            if ($isAuth -and $attempt -lt $MaxAttempts) {
                Write-Host "  Azure token expired during run command - refreshing and retrying ($attempt/$($MaxAttempts - 1))..." -ForegroundColor Yellow
                continue
            }
            throw
        }
    }
}

function Get-PocVmContext {
    <#
      Resolves the VM identity (resource group, name, subscription) from a PoC
      environment hashtable. Returns $null when no SQL VM is deployed.
    #>
    [CmdletBinding()]
    param([hashtable]$PocEnv)

    if (-not $PocEnv) { $PocEnv = Get-PocEnv }
    $vm = $PocEnv['VM_NAME']
    if (-not $vm) { return $null }
    return @{
        ResourceGroup = $PocEnv['AZURE_RESOURCE_GROUP']
        VMName        = $vm
        Subscription  = $PocEnv['AZURE_SUBSCRIPTION_ID']
    }
}

function Open-PocVmSqlPort {
    <#
      TEMPORARILY makes the SQL VM reachable on TCP 1433 from this machine:
      ensures the SQL Server TCP/IP protocol is enabled + pinned to 1433 (a
      one-time change that persists on the VM) and adds a Windows Firewall rule
      'PoC-Temp-SQL-1433'. Runs entirely via the Azure control plane
      (Invoke-AzVMRunCommand) so it needs no existing 1433 connectivity.
      Idempotent - safe to call before every VM stage.
    #>
    [CmdletBinding()]
    param([hashtable]$PocEnv)

    $c = Get-PocVmContext -PocEnv $PocEnv
    if (-not $c) { return }

    $openScript = @'
$ErrorActionPreference = 'Stop'
$instId = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL' -ErrorAction Stop).MSSQLSERVER
$tcpKey = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$instId\MSSQLServer\SuperSocketNetLib\Tcp"
$changed = $false
if ((Get-ItemProperty -Path $tcpKey -Name Enabled -ErrorAction SilentlyContinue).Enabled -ne 1) {
    Set-ItemProperty -Path $tcpKey -Name Enabled -Value 1; $changed = $true
}
if (Test-Path "$tcpKey\IPAll") {
    $cur = Get-ItemProperty -Path "$tcpKey\IPAll"
    if ($cur.TcpPort -ne '1433') { Set-ItemProperty -Path "$tcpKey\IPAll" -Name TcpPort -Value '1433'; $changed = $true }
    if ($cur.TcpDynamicPorts -ne '') { Set-ItemProperty -Path "$tcpKey\IPAll" -Name TcpDynamicPorts -Value ''; $changed = $true }
}
if ($changed) { Restart-Service -Name 'MSSQLSERVER' -Force; Start-Sleep -Seconds 20 }
if (-not (Get-NetFirewallRule -DisplayName 'PoC-Temp-SQL-1433' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName 'PoC-Temp-SQL-1433' -Direction Inbound -Protocol TCP -LocalPort 1433 -Action Allow | Out-Null
}
Write-Output 'VM_PORT_OPEN'
'@

    $r = Invoke-PocVMRunCommand -ResourceGroupName $c.ResourceGroup -VMName $c.VMName `
        -ScriptString $openScript -Subscription $c.Subscription
    $o = ($r.Value | ForEach-Object { $_.Message }) -join "`n"
    if ($o -match 'VM_PORT_OPEN') {
        Write-Host "  SQL port 1433 temporarily open on $($c.VMName)." -ForegroundColor DarkGray
    } else {
        Write-Warning "Could not confirm SQL port open on $($c.VMName). Output:`n$o"
    }
}

function Close-PocVmSqlPort {
    <#
      Reverses Open-PocVmSqlPort by removing the temporary Windows Firewall rule,
      so TCP 1433 is no longer reachable from the Internet once a stage finishes.
      Never throws - a demo run should not fail just because cleanup hiccuped.
    #>
    [CmdletBinding()]
    param([hashtable]$PocEnv)

    $c = Get-PocVmContext -PocEnv $PocEnv
    if (-not $c) { return }

    $closeScript = @'
Remove-NetFirewallRule -DisplayName 'PoC-Temp-SQL-1433' -ErrorAction SilentlyContinue
Write-Output 'VM_PORT_CLOSED'
'@
    try {
        $r = Invoke-PocVMRunCommand -ResourceGroupName $c.ResourceGroup -VMName $c.VMName `
            -ScriptString $closeScript -Subscription $c.Subscription
        $o = ($r.Value | ForEach-Object { $_.Message }) -join "`n"
        if ($o -match 'VM_PORT_CLOSED') {
            Write-Host "  SQL port 1433 closed on $($c.VMName)." -ForegroundColor DarkGray
        } else {
            Write-Warning "Could not confirm SQL port closure. Remove firewall rule 'PoC-Temp-SQL-1433' on $($c.VMName) manually.`n$o"
        }
    } catch {
        Write-Warning "Failed to close SQL port on $($c.VMName): $($_.Exception.Message). Remove firewall rule 'PoC-Temp-SQL-1433' manually."
    }
}

function Initialize-PocVmSqlServer {
    <#
      Robustly prepares SQL Server on the VM for the PoC:
        1. Enables mixed-mode authentication via the effective LoginMode registry
           key (xp_instance_regwrite is unreliable on these images) + restart.
        2. Creates/repairs the SQL-auth sysadmin login and the demo database.

      The VM Run Command executes as NT AUTHORITY\SYSTEM, which is NOT a SQL
      sysadmin on the marketplace image, so the DDL is run under the VM local
      administrator via a batch-logon token + thread impersonation + SqlClient
      (Integrated Security). It also grants SYSTEM sysadmin so later Run Command
      operations work directly. Idempotent.
    #>
    [CmdletBinding()]
    param(
        [hashtable]$PocEnv,
        [Parameter(Mandatory)][string]$VmSaLogin,
        [Parameter(Mandatory)][string]$VmSaPassword,
        [Parameter(Mandatory)][string]$VmDatabase
    )

    if (-not $PocEnv) { $PocEnv = Get-PocEnv }
    $c = Get-PocVmContext -PocEnv $PocEnv
    if (-not $c) { throw "No SQL VM in this deployment (VM_NAME missing)." }

    $adminPw = $PocEnv['ADMIN_PASSWORD']
    if (-not $adminPw) { throw "ADMIN_PASSWORD not found in azd env - cannot bootstrap VM SQL authentication." }
    $adminUser = az vm show -g $c.ResourceGroup -n $c.VMName --query "osProfile.adminUsername" -o tsv 2>$null
    if (-not $adminUser) { $adminUser = 'sqlvmadmin' }

    $adminPwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($adminPw))
    $saPwB64    = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($VmSaPassword))

    $script = @'
$ErrorActionPreference = 'Stop'
# --- 1. Ensure mixed-mode authentication (effective registry key + restart) ---
$instId = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL').MSSQLSERVER
$svcKey = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$instId\MSSQLServer"
$mode = (Get-ItemProperty -Path $svcKey -Name LoginMode -ErrorAction SilentlyContinue).LoginMode
if ($mode -ne 2) {
    Set-ItemProperty -Path $svcKey -Name LoginMode -Value 2 -Type DWord
    Restart-Service -Name 'MSSQLSERVER' -Force
    (Get-Service MSSQLSERVER).WaitForStatus('Running','00:01:30')
    Start-Sleep -Seconds 8
}
# --- 2. Create login + DB as the VM admin (SYSTEM is not a SQL sysadmin here) ---
$adminUser = '__ADMINUSER__'
$adminPw = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__ADMINPW__'))
$saPw = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__SAPW__'))
$sa = '__SALOGIN__'; $db = '__DB__'
Add-Type -Namespace Imp -Name Native -MemberDefinition @"
[System.Runtime.InteropServices.DllImport("advapi32.dll", SetLastError=true, CharSet=System.Runtime.InteropServices.CharSet.Unicode)] public static extern bool LogonUser(string u,string d,string p,int lt,int lp,out System.IntPtr tok);
[System.Runtime.InteropServices.DllImport("advapi32.dll", SetLastError=true)] public static extern bool ImpersonateLoggedOnUser(System.IntPtr tok);
[System.Runtime.InteropServices.DllImport("advapi32.dll", SetLastError=true)] public static extern bool RevertToSelf();
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError=true)] public static extern bool CloseHandle(System.IntPtr h);
"@
$tok = [IntPtr]::Zero
$useImp = [Imp.Native]::LogonUser($adminUser, $env:COMPUTERNAME, $adminPw, 4, 0, [ref]$tok)
if ($useImp) { [void][Imp.Native]::ImpersonateLoggedOnUser($tok) }
try {
    $cn = New-Object System.Data.SqlClient.SqlConnection "Server=localhost;Database=master;Integrated Security=SSPI;TrustServerCertificate=true"
    $cn.Open()
    $batches = @(
        "IF SUSER_ID('$sa') IS NULL CREATE LOGIN [$sa] WITH PASSWORD='$saPw', CHECK_POLICY=OFF; ELSE ALTER LOGIN [$sa] WITH PASSWORD='$saPw', CHECK_POLICY=OFF;",
        "ALTER LOGIN [$sa] ENABLE;",
        "IF IS_SRVROLEMEMBER('sysadmin','$sa')=0 ALTER SERVER ROLE sysadmin ADD MEMBER [$sa];",
        "IF SUSER_ID('NT AUTHORITY\SYSTEM') IS NOT NULL AND IS_SRVROLEMEMBER('sysadmin','NT AUTHORITY\SYSTEM')=0 ALTER SERVER ROLE sysadmin ADD MEMBER [NT AUTHORITY\SYSTEM];",
        "IF DB_ID('$db') IS NULL CREATE DATABASE [$db];"
    )
    foreach ($b in $batches) { $cmd = $cn.CreateCommand(); $cmd.CommandText = $b; [void]$cmd.ExecuteNonQuery() }
    $cn.Close()
} finally {
    if ($useImp) { [void][Imp.Native]::RevertToSelf(); if ($tok -ne [IntPtr]::Zero) { [void][Imp.Native]::CloseHandle($tok) } }
}
Write-Output 'VM_BOOTSTRAP_OK'
'@

    $script = $script.Replace('__ADMINUSER__', $adminUser).
        Replace('__ADMINPW__', $adminPwB64).
        Replace('__SAPW__', $saPwB64).
        Replace('__SALOGIN__', $VmSaLogin).
        Replace('__DB__', $VmDatabase)

    $r = Invoke-PocVMRunCommand -ResourceGroupName $c.ResourceGroup -VMName $c.VMName `
        -ScriptString $script -Subscription $c.Subscription
    $out = ($r.Value | ForEach-Object { $_.Message }) -join "`n"
    if ($out -notmatch 'VM_BOOTSTRAP_OK') {
        throw "VM SQL bootstrap did not confirm success. Output:`n$out"
    }
}

function Invoke-PocSql {
    <#
      Thin, safe wrapper around Invoke-Sqlcmd. Prefers SQL authentication.
      Use -Query or -InputFile. Returns rows for SELECTs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ServerInstance,
        [Parameter(Mandatory)][string]$Database,
        [string]$Query,
        [string]$InputFile,
        [string]$Username,
        [string]$Password,
        [int]$QueryTimeout = 300,
        [switch]$TrustServerCertificate
    )
    Ensure-SqlServerModule

    $params = @{
        ServerInstance = $ServerInstance
        Database       = $Database
        QueryTimeout   = $QueryTimeout
        ErrorAction    = 'Stop'
    }
    if ($Query)     { $params.Query = $Query }
    if ($InputFile) { $params.InputFile = $InputFile }
    if ($Username)  { $params.Username = $Username; $params.Password = $Password }
    if ($TrustServerCertificate) { $params.TrustServerCertificate = $true }
    # Azure SQL requires encryption; harmless for the VM too.
    $params.Encrypt = 'Mandatory'

    return Invoke-Sqlcmd @params
}

function Get-PocTargets {
    <#
      Resolves connection info for the demo databases as an array of target objects.
      Each object: Name, ServerInstance, Database, Encrypt, Trust.
      Includes Azure (always, if provisioned) and the VM (if reachable).
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Azure','Vm','Both')][string]$Target = 'Azure',
        [string]$VmDatabase = 'PocBankingAuditDbOnVm'
    )
    $env = Get-PocEnv
    $targets = @()
    if ($Target -in @('Azure','Both') -and $env['SQL_SERVER_FQDN']) {
        $targets += [pscustomobject]@{
            Name = 'AzureSQL'; ServerInstance = $env['SQL_SERVER_FQDN'];
            Database = $env['SQL_DATABASE_NAME']; Encrypt = 'Mandatory'; Trust = $false
        }
    }
    if ($Target -in @('Vm','Both') -and $env['VM_PUBLIC_IP']) {
        $targets += [pscustomobject]@{
            Name = 'SqlServerVM'; ServerInstance = "$($env['VM_PUBLIC_IP']),1433";
            Database = $VmDatabase; Encrypt = 'Optional'; Trust = $true
        }
    }
    return $targets
}

function Invoke-DemoQuery {
    <#
      Runs a query as a demo persona (SQL auth) to produce attributed audit records.
      Returns rows on success; swallows permission-denied errors (they are still audited)
      unless -ThrowOnError is set.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Target,
        [Parameter(Mandatory)][string]$User,
        [Parameter(Mandatory)][string]$Password,
        [Parameter(Mandatory)][string]$Query,
        [int]$QueryTimeout = 120,
        [switch]$ThrowOnError
    )
    Ensure-SqlServerModule
    try {
        $p = @{
            ServerInstance = $Target.ServerInstance; Database = $Target.Database
            Username = $User; Password = $Password; Query = $Query
            QueryTimeout = $QueryTimeout; Encrypt = $Target.Encrypt; ErrorAction = 'Stop'
        }
        if ($Target.Trust) { $p.TrustServerCertificate = $true }
        return Invoke-Sqlcmd @p
    } catch {
        if ($ThrowOnError) { throw }
        Write-Host "    (expected/permission or demo error captured in audit) $($_.Exception.Message.Split([Environment]::NewLine)[0])" -ForegroundColor DarkYellow
        return $null
    }
}

function Write-Scenario {
    param([string]$Title, [string]$Message)
    Write-Host ""
    Write-Host ("=" * 78) -ForegroundColor DarkCyan
    Write-Host "  $Title" -ForegroundColor Cyan
    if ($Message) { Write-Host "  $Message" -ForegroundColor Gray }
    Write-Host ("=" * 78) -ForegroundColor DarkCyan
}

function Write-Validation {
    param([string]$Kql)
    Write-Host "  Validate in Log Analytics:" -ForegroundColor DarkYellow
    foreach ($l in ($Kql -split "`n")) { Write-Host "    $l" -ForegroundColor DarkGray }
}
