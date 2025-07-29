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

function Write-Title($title) {
    Write-Output "#`n# $title`n#"
}

# wrap the choco command (to make sure this script aborts when it fails).
function Start-Choco([string[]]$Arguments, [int[]]$SuccessExitCodes=@(0)) {
    $command, $commandArguments = $Arguments
    if ($command -eq 'install') {
        $Arguments = @($command, '--no-progress') + $commandArguments
    }
    for ($n = 0; $n -lt 10; ++$n) {
        if ($n) {
            # NB sometimes choco fails with "The package was not found with the source(s) listed."
            #    but normally its just really a transient "network" error.
            Write-Host "Retrying choco install..."
            Start-Sleep -Seconds 3
        }
        &C:\ProgramData\chocolatey\bin\choco.exe @Arguments
        if ($SuccessExitCodes -Contains $LASTEXITCODE) {
            return
        }
    }
    throw "$(@('choco')+$Arguments | ConvertTo-Json -Compress) failed with exit code $LASTEXITCODE"
}
function choco {
    Start-Choco $Args
}

function exec([ScriptBlock]$externalCommand, [string]$stderrPrefix='', [int[]]$successExitCodes=@(0)) {
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        &$externalCommand 2>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                "$stderrPrefix$_"
            } else {
                "$_"
            }
        }
        if ($LASTEXITCODE -notin $successExitCodes) {
            throw "$externalCommand failed with exit code $LASTEXITCODE"
        }
    } finally {
        $ErrorActionPreference = $eap
    }
}

# install chocolatey.
Write-Host "Installing chocolatey..."
Invoke-WebRequest https://chocolatey.org/install.ps1 -UseBasicParsing | Invoke-Expression
Import-Module C:\ProgramData\chocolatey\helpers\chocolateyInstaller.psm1
Update-SessionEnvironment

# install dependencies.
Write-Host "Installing the app dependencies..."
# see https://community.chocolatey.org/packages/nssm
# see https://nssm.cc
# renovate: datasource=nuget:chocolatey depName=nssm
$nssmVersion = '2.24.101.20180116'
# see https://community.chocolatey.org/packages/nodejs-lts
# see https://nodejs.org/en/
# renovate: datasource=nuget:chocolatey depName=nodejs-lts versioning=node
$nodejsVersion = '22.15.1'
choco install -y nssm "--version=$nssmVersion"
choco install -y nodejs-lts "--version=$nodejsVersion"
Update-SessionEnvironment

# create an example http server and run it as a windows service.
Write-Host "Installing the app..."
$serviceName = 'app'
$serviceUsername = "NT SERVICE\$serviceName"
$serviceHome = 'c:\app'
mkdir -Force $serviceHome | Out-Null
Push-Location $serviceHome
Set-Content -Encoding ascii -Path main.js -Value @'
import http from "http";
import { SSMClient, GetParameterCommand } from "@aws-sdk/client-ssm";

function createRequestListener(instanceIdentity) {
    return async (request, response) => {
        const instanceCredentials = await getInstanceCredentials();
        const instanceRoleMessageParameter = await getInstanceRoleParameter(instanceIdentity.region, instanceCredentials.role, "message");
        const serverAddress = `${request.socket.localAddress}:${request.socket.localPort}`;
        const clientAddress = `${request.socket.remoteAddress}:${request.socket.remotePort}`;
        const message = `Instance ID: ${instanceIdentity.instanceId}
Instance Image ID: ${instanceIdentity.imageId}
Instance Region: ${instanceIdentity.region}
Instance Role: ${instanceCredentials.role}
Instance Role Message Parameter: ${instanceRoleMessageParameter}
Instance Credentials Expire At: ${instanceCredentials.credentials.Expiration}
Node.js Version: ${process.versions.node}
Server Address: ${serverAddress}
Client Address: ${clientAddress}
Request URL: ${request.url}
`;
        console.log(message);
        response.writeHead(200, {"Content-Type": "text/plain"});
        response.write(message);
        response.end();
    };
}

function main(instanceIdentity, port) {
    const server = http.createServer(createRequestListener(instanceIdentity));
    server.listen(port);
}

// see https://docs.aws.amazon.com/AWSJavaScriptSDK/v3/latest/client/ssm/command/GetParameterCommand/
async function getInstanceRoleParameter(region, instanceRole, parameterName) {
    const client = new SSMClient({
        region: region,
    });
    const response = await client.send(new GetParameterCommand({
        Name: `/${instanceRole}/${parameterName}`,
    }));
    return response.Parameter.Value;
}

// see https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/iam-roles-for-amazon-ec2.html#instance-metadata-security-credentials
async function getInstanceCredentials() {
    const tokenResponse = await fetch("http://169.254.169.254/latest/api/token", {
        method: "PUT",
        headers: {
            "X-aws-ec2-metadata-token-ttl-seconds": 30,
        }
    });
    if (!tokenResponse.ok) {
        throw new Error(`Failed to fetch instance token: ${tokenResponse.status} ${tokenResponse.statusText}`);
    }
    const token = await tokenResponse.text();
    const instanceRoleResponse = await fetch(`http://169.254.169.254/latest/meta-data/iam/security-credentials`, {
        headers: {
            "X-aws-ec2-metadata-token": token,
        }
    });
    if (!instanceRoleResponse.ok) {
        throw new Error(`Failed to fetch instance role: ${instanceRoleResponse.status} ${instanceRoleResponse.statusText}`);
    }
    const instanceRole = (await instanceRoleResponse.text()).trim();
    const instanceCredentialsResponse = await fetch(`http://169.254.169.254/latest/meta-data/iam/security-credentials/${instanceRole}`, {
        headers: {
            "X-aws-ec2-metadata-token": token,
        }
    });
    if (!instanceCredentialsResponse.ok) {
        throw new Error(`Failed to fetch ${instanceRole} instance role credentials: ${instanceCredentialsResponse.status} ${instanceCredentialsResponse.statusText}`);
    }
    const instanceCredentials = await instanceCredentialsResponse.json();
    return {
        role: instanceRole,
        credentials: instanceCredentials,
    };
}

// see https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instance-identity-documents.html
// see https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instancedata-data-retrieval.html
// see https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instance-metadata-v2-how-it-works.html
async function getInstanceIdentity() {
    const tokenResponse = await fetch("http://169.254.169.254/latest/api/token", {
        method: "PUT",
        headers: {
            "X-aws-ec2-metadata-token-ttl-seconds": 30,
        }
    });
    if (!tokenResponse.ok) {
        throw new Error(`Failed to fetch instance token: ${tokenResponse.status} ${tokenResponse.statusText}`);
    }
    const token = await tokenResponse.text();
    const instanceIdentityResponse = await fetch("http://169.254.169.254/latest/dynamic/instance-identity/document", {
        headers: {
            "X-aws-ec2-metadata-token": token,
        }
    });
    if (!instanceIdentityResponse.ok) {
        throw new Error(`Failed to fetch instance metadata: ${instanceIdentityResponse.status} ${instanceIdentityResponse.statusText}`);
    }
    const instanceIdentity = await instanceIdentityResponse.json();
    return instanceIdentity;
}

main(await getInstanceIdentity(), process.argv[2]);
'@
Set-Content -Encoding ascii -Path package.json -Value @'
{
    "name": "app",
    "description": "example application",
    "version": "1.0.0",
    "license": "MIT",
    "type": "module",
    "main": "main.js",
    "dependencies": {}
}
'@
# see https://www.npmjs.com/package/@aws-sdk/client-ssm
# renovate: datasource=npm depName=@aws-sdk/client-ssm
$awsSdkClientSsmVersion = '3.849.0'
exec {npm install --save "@aws-sdk/client-ssm@$awsSdkClientSsmVersion"}

# create the windows service using a managed service account.
Write-Host "Creating the $serviceName service..."
nssm install $serviceName (Get-Command node.exe).Path
nssm set $serviceName AppParameters main.js 80
nssm set $serviceName AppDirectory $serviceHome
nssm set $serviceName Start SERVICE_AUTO_START
nssm set $serviceName AppRotateFiles 1
nssm set $serviceName AppRotateOnline 1
nssm set $serviceName AppRotateSeconds 86400
nssm set $serviceName AppRotateBytes 1048576
nssm set $serviceName AppStdout $serviceHome\logs\service-stdout.log
nssm set $serviceName AppStderr $serviceHome\logs\service-stderr.log
[string[]]$result = sc.exe sidtype $serviceName unrestricted
if ($result -ne '[SC] ChangeServiceConfig2 SUCCESS') {
    throw "sc.exe sidtype failed with $result"
}
[string[]]$result = sc.exe config $serviceName obj= $serviceUsername
if ($result -ne '[SC] ChangeServiceConfig SUCCESS') {
    throw "sc.exe config failed with $result"
}
[string[]]$result = sc.exe failure $serviceName reset= 0 actions= restart/60000
if ($result -ne '[SC] ChangeServiceConfig2 SUCCESS') {
    throw "sc.exe failure failed with $result"
}

# create the logs directory and grant fullcontrol to the service.
$logsDirectory = mkdir "$serviceHome\logs"
$acl = New-Object Security.AccessControl.DirectorySecurity
$acl.SetAccessRuleProtection($true, $false)
@(
    'SYSTEM'
    'Administrators'
    $serviceUsername
) | ForEach-Object {
    $acl.AddAccessRule((
        New-Object `
            Security.AccessControl.FileSystemAccessRule(
                $_,
                'FullControl',
                'ContainerInherit,ObjectInherit',
                'None',
                'Allow')))
}
$logsDirectory.SetAccessControl($acl)

# finally start the service.
Start-Service $serviceName
Pop-Location

# create a firewall rule to accept incoming traffic on port 80.
New-NetFirewallRule `
    -Name 'app' `
    -DisplayName 'app' `
    -Direction Inbound `
    -LocalPort 80 `
    -Protocol TCP `
    -Action Allow `
    | Out-Null

# try it.
Write-Host "Trying the app..."
Start-Sleep -Milliseconds 500
Invoke-RestMethod http://localhost/try

# set $LASTEXITCODE to 0 because the AWS supplied scripts are checking for this variable value.
cmd.exe /c exit 0
