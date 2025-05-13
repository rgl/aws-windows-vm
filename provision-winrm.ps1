Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
trap {
    Write-Host
    Write-Host "ERROR: $_"
    ($_.ScriptStackTrace -split '\r?\n') -replace '^(.*)$','ERROR: $1' | Write-Host
    ($_.Exception.ToString() -split '\r?\n') -replace '^(.*)$','ERROR EXCEPTION: $1' | Write-Host
    # set $LASTEXITCODE to 1 because the AWS supplied scripts are checking for this variable value.
    cmd.exe /c exit 1
    Exit 1
}

# configure WinRM.
Write-Output 'Configuring WinRM...'
winrm quickconfig -quiet
winrm set winrm/config/service/auth '@{CredSSP="true"}'
# make sure the WinRM service startup type is delayed-auto
# even when the default config is auto (e.g. Windows 2019
# changed that default).
# WARN do not be tempted to change the default WinRM service startup type from
#      delayed-auto to auto, as the later proved to be unreliable.
$result = sc.exe config WinRM start= delayed-auto
if ($result -ne '[SC] ChangeServiceConfig SUCCESS') {
    throw "sc.exe config failed with $result"
}

# dump the WinRM configuration.
Write-Output 'WinRM Configuration:'
winrm enumerate winrm/config/listener
winrm get winrm/config
winrm id

# make sure winrm can be accessed from any network location.
# NB by default, the ethernet interface is in the Public profile, and in that
#    profile, the default firewall rule, Windows Remote Management (HTTP-In),
#    only allows connections from the Local subnet. so we have to add a new
#    firewall rule.
New-NetFirewallRule `
    -DisplayName WINRM-HTTP-In-TCP-RGL `
    -Direction Inbound `
    -Action Allow `
    -Protocol TCP `
    -LocalPort 5985 `
    | Out-Null

# set $LASTEXITCODE to 0 because the AWS supplied scripts are checking for this variable value.
cmd.exe /c exit 0
