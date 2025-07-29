# About

[![Lint](https://github.com/rgl/aws-windows-vm/actions/workflows/lint.yml/badge.svg)](https://github.com/rgl/aws-windows-vm/actions/workflows/lint.yml)

An example Windows VM running in a AWS EC2 Instance.

This will:

* Create a VPC.
  * Configure a Internet Gateway.
* Create a Systems Manager ([aka SSM](https://docs.aws.amazon.com/systems-manager/latest/userguide/what-is-systems-manager.html#service-naming-history)) Parameter.
* Create a EC2 Instance.
  * Assign a Public IP IPv4 address.
  * Assign a Public IP IPv6 address.
  * Assign a IAM Role.
    * Include the [AmazonSSMManagedInstanceCore Policy](https://docs.aws.amazon.com/aws-managed-policy/latest/reference/AmazonSSMManagedInstanceCore.html).
  * Initialize.
    * Configure WinRM.
    * Configure SSH.
    * Install a example application.
      * Get the [Instance Identity Document](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instance-identity-documents.html) from the [EC2 Instance Metadata Service](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-metadata.html).
      * Get a Parameter from the [Systems Manager Parameter Store](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html).
      * Get the [Instance (IAM) Role Credentials](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/iam-roles-for-amazon-ec2.html#instance-metadata-security-credentials).
  * Wait for the instance to be ready.

# Usage (on a Ubuntu Desktop)

Install Visual Studio Code and the Dev Container plugin.

Install the dependencies:

* [Visual Studio Code](https://code.visualstudio.com).
* [Dev Container plugin](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers).

Open this directory with the Dev Container plugin.

Open the Visual Studio Code Terminal.

Set the AWS Account credentials using SSO, e.g.:

```bash
# set the account credentials.
# NB the aws cli stores these at ~/.aws/config.
# NB this is equivalent to manually configuring SSO using aws configure sso.
# see https://docs.aws.amazon.com/cli/latest/userguide/sso-configure-profile-token.html#sso-configure-profile-token-manual
# see https://docs.aws.amazon.com/cli/latest/userguide/sso-configure-profile-token.html#sso-configure-profile-token-auto-sso
cat >secrets.sh <<'EOF'
# set the environment variables to use a specific profile.
# NB use aws configure sso to configure these manually.
# e.g. use the pattern <aws-sso-session>-<aws-account-id>-<aws-role-name>
export aws_sso_session='example'
export aws_sso_start_url='https://example.awsapps.com/start'
export aws_sso_region='eu-west-1'
export aws_sso_account_id='123456'
export aws_sso_role_name='AdministratorAccess'
export AWS_PROFILE="$aws_sso_session-$aws_sso_account_id-$aws_sso_role_name"
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_DEFAULT_REGION
# configure the ~/.aws/config file.
# NB unfortunately, I did not find a way to create the [sso-session] section
#    inside the ~/.aws/config file using the aws cli. so, instead, manage that
#    file using python.
python3 <<'PY_EOF'
import configparser
import os
aws_sso_session = os.getenv('aws_sso_session')
aws_sso_start_url = os.getenv('aws_sso_start_url')
aws_sso_region = os.getenv('aws_sso_region')
aws_sso_account_id = os.getenv('aws_sso_account_id')
aws_sso_role_name = os.getenv('aws_sso_role_name')
aws_profile = os.getenv('AWS_PROFILE')
config = configparser.ConfigParser()
aws_config_directory_path = os.path.expanduser('~/.aws')
aws_config_path = os.path.join(aws_config_directory_path, 'config')
if os.path.exists(aws_config_path):
  config.read(aws_config_path)
config[f'sso-session {aws_sso_session}'] = {
  'sso_start_url': aws_sso_start_url,
  'sso_region': aws_sso_region,
  'sso_registration_scopes': 'sso:account:access',
}
config[f'profile {aws_profile}'] = {
  'sso_session': aws_sso_session,
  'sso_account_id': aws_sso_account_id,
  'sso_role_name': aws_sso_role_name,
  'region': aws_sso_region,
}
os.makedirs(aws_config_directory_path, mode=0o700, exist_ok=True)
with open(aws_config_path, 'w') as f:
  config.write(f)
PY_EOF
unset aws_sso_start_url
unset aws_sso_region
unset aws_sso_session
unset aws_sso_account_id
unset aws_sso_role_name
# show the user, user amazon resource name (arn), and the account id, of the
# profile set in the AWS_PROFILE environment variable.
if ! aws sts get-caller-identity >/dev/null 2>&1; then
  aws sso login
fi
aws sts get-caller-identity
EOF
```

Or, set the AWS Account credentials using an Access Key, e.g.:

```bash
# set the account credentials.
# NB get these from your aws account iam console.
#    see Managing access keys (console) at
#        https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_access-keys.html#Using_CreateAccessKey
cat >secrets.sh <<'EOF'
export AWS_ACCESS_KEY_ID='TODO'
export AWS_SECRET_ACCESS_KEY='TODO'
unset AWS_PROFILE
# set the default region.
export AWS_DEFAULT_REGION='eu-west-1'
# show the user, user amazon resource name (arn), and the account id.
aws sts get-caller-identity
EOF
```

Review `main.tf`.

Load the secrets into the current shell session:

```bash
source secrets.sh
```

Initialize terraform:

```bash
make terraform-init
```

Launch the example:

```bash
rm -f terraform.log
make terraform-apply
```

Show the terraform state:

```bash
make terraform-show
```

Show the `Administrator` user password:

```bash
while true; do
  administrator_password="$(aws ec2 get-password-data \
    --instance-id "$(terraform output --raw app_instance_id)" \
    --priv-launch-key ~/.ssh/id_rsa \
    | jq -r .PasswordData)"
  if [ -n "$administrator_password" ]; then
    echo "Administrator password: $administrator_password"
    break
  fi
  sleep 5
done
```

Connect to the instance RDP server as the `Administrator` user:

**NB** This does not run from the dev container, so you should echo it here,
and then execute the resulting command on your host.

```bash
remmina "rdp://Administrator@$(terraform output --raw app_ip_address)"
remmina "rdp://Administrator@$(terraform output --raw app_ipv6_address)"
```

Do a connectivity check for the WinRM server endpoint, which should return a
`405 Method Not Allowed` status code when the server is ready and you can
connect to it:

```bash
curl --verbose "http://$(terraform output --raw app_ip_address):5985/wsman"
```

Repeat, using IPv6, but you have to do it outside of the dev container, as it
does not have IPv6 support:

**NB** This does not run from the dev container, so you should echo it here,
and then execute the resulting command on your host.

```bash
curl --verbose "http://[$(terraform output --raw app_ipv6_address)]:5985/wsman"
```

Test the WinRM connection, which should not return any error:

**NB** This does not run from the dev container, so you should echo it here,
and then execute the resulting command on your host.

**NB** You must first install the [`winps` container image](https://github.com/rgl/winps).

```bash
administrator_password="$(aws ec2 get-password-data \
  --instance-id "$(terraform output --raw app_instance_id)" \
  --priv-launch-key ~/.ssh/id_rsa \
  | jq -r .PasswordData)"
docker run --rm \
  "--add-host=winrm.test:$(terraform output --raw app_ip_address)" \
  winps \
  winps \
  execute \
  --host=winrm.test \
  --encryption=auto \
  --username=Administrator \
  "--password=$administrator_password"
```

Get the instance ssh host public keys, convert them to the knowns hosts format,
and show their fingerprints:

```bash
./aws-ssm-get-sshd-public-keys.sh \
  "$(terraform output --raw app_instance_id)" \
  | tail -2 \
  | jq -r .sshd_public_keys \
  | sed "s/^/$(terraform output --raw app_instance_id),$(terraform output --raw app_ip_address),$(terraform output --raw app_ipv6_address) /" \
  > app-ssh-known-hosts.txt
ssh-keygen -l -f app-ssh-known-hosts.txt
```

Using your ssh client, open a shell inside the VM and execute some commands:

```bash
ssh \
  -o UserKnownHostsFile=app-ssh-known-hosts.txt \
  "Administrator@$(terraform output --raw app_ip_address)"
powershell
$PSVersionTable
whoami /all
winrm id
winrm enumerate winrm/config/listener
winrm get winrm/config
&"C:\Program Files\Amazon\SSM\ssm-cli.exe" get-instance-information
&"C:\Program Files\Amazon\SSM\ssm-cli.exe" get-diagnostics
# List all the AWS endpoints that the SSM agent uses
&"C:\Program Files\Amazon\SSM\ssm-cli.exe" get-diagnostics |
  Select-String -Pattern '([a-z0-9.-]+\.amazonaws\.com)' -AllMatches |
  ForEach-Object { $_.Matches.Groups[1].Value } |
  Sort-Object -Unique |
  ForEach-Object {
    $endpoint = $_
    (Resolve-DnsName -Name $endpoint -Type A -QuickTimeout).IPAddress |
    Sort-Object |
    ForEach-Object { "$endpoint`: $_" }
    (Resolve-DnsName -Name $endpoint -Type AAAA -QuickTimeout).IPAddress |
    Sort-Object |
    ForEach-Object { "$endpoint`: $_" }
  }
curl.exe --verbose http://localhost/try
curl.exe --verbose 'http://[::1]/try'
exit # exit the powershell.exe shell.
exit # exit the cmd.exe shell.
```

Using your ssh client, access using ipv6:

**NB** This does not run from the dev container, so you should echo it here,
and then execute the resulting command on your host.

```bash
ssh \
  -6 \
  -o UserKnownHostsFile=app-ssh-known-hosts.txt \
  "Administrator@$(terraform output --raw app_ipv6_address)"
echo %SSH_CLIENT%
echo %SSH_CONNECTION%
curl -6 https://ip6.me/api/
exit
```

Using your ssh client, and [aws ssm session manager to proxy the ssh connection](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-getting-started-enable-ssh-connections.html), open a shell inside the VM and execute some commands:

```bash
ssh \
  -o UserKnownHostsFile=app-ssh-known-hosts.txt \
  -o ProxyCommand='aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p' \
  "Administrator@$(terraform output --raw app_instance_id)"
powershell
$PSVersionTable
whoami /all
&"C:\Program Files\Amazon\SSM\ssm-cli.exe" get-instance-information
&"C:\Program Files\Amazon\SSM\ssm-cli.exe" get-diagnostics
curl.exe --verbose http://localhost/try
curl.exe --verbose 'http://[::1]/try'
exit # exit the powershell.exe shell.
exit # exit the cmd.exe shell.
```

Using [aws ssm session manager](https://docs.aws.amazon.com/cli/latest/reference/ssm/start-session.html), open a `powershell` shell inside the VM and execute some commands:

```bash
# NB this executes the command inside a windows powershell shell. to switch to a
#    different one, see the next example.
# NB the default ssm session --document-name is SSM-SessionManagerRunShell.
#    NB that document is created in our account when session manager is used
#       for the first time.
# see https://docs.aws.amazon.com/systems-manager/latest/userguide/getting-started-default-session-document.html
# see aws ssm describe-document --name SSM-SessionManagerRunShell
aws ssm start-session --target "$(terraform output --raw app_instance_id)"
$PSVersionTable
whoami /all
&"C:\Program Files\Amazon\SSM\ssm-cli.exe" get-instance-information
&"C:\Program Files\Amazon\SSM\ssm-cli.exe" get-diagnostics
curl.exe --verbose http://localhost/try
curl.exe --verbose 'http://[::1]/try'
exit # exit the powershell.exe shell.
```

Using [aws ssm session manager](https://docs.aws.amazon.com/cli/latest/reference/ssm/start-session.html), open a `cmd` shell inside the VM and execute some commands:

```bash
# NB this executes the command inside a powershell shell, but we immediately
#    start the cmd shell.
# NB the default ssm session --document-name is SSM-SessionManagerRunShell which
#    is created in our account when session manager is used the first time.
# see aws ssm describe-document --name AWS-StartInteractiveCommand --query 'Document.Parameters[*]'
# see aws ssm describe-document --name AWS-StartNonInteractiveCommand --query 'Document.Parameters[*]'
aws ssm start-session \
  --document-name AWS-StartInteractiveCommand \
  --parameters '{"command":["cmd.exe"]}' \
  --target "$(terraform output --raw app_instance_id)"
ver
whoami /all
"C:\Program Files\Amazon\SSM\ssm-cli.exe" get-instance-information
"C:\Program Files\Amazon\SSM\ssm-cli.exe" get-diagnostics
curl --verbose http://localhost/try
curl --verbose http://[::1]/try
exit
```

Destroy the example:

```bash
make terraform-destroy
```

# References

* [Environment variables to configure the AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-envvars.html)
* [Token provider configuration with automatic authentication refresh for AWS IAM Identity Center](https://docs.aws.amazon.com/cli/latest/userguide/sso-configure-profile-token.html) (SSO)
* [Managing access keys (console)](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_access-keys.html#Using_CreateAccessKey)
* [AWS General Reference](https://docs.aws.amazon.com/general/latest/gr/Welcome.html)
  * [Amazon Resource Names (ARNs)](https://docs.aws.amazon.com/general/latest/gr/aws-arns-and-namespaces.html)
* [Connect to the internet using an internet gateway](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Internet_Gateway.html#vpc-igw-internet-access)
* [Retrieve instance metadata](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instancedata-data-retrieval.html)
* [How Instance Metadata Service Version 2 works](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instance-metadata-v2-how-it-works.html)
* [Configure your Amazon EC2 Windows instance](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-windows-instances.html)
* [How Amazon EC2 handles user data for Windows instances](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html#ec2-windows-user-data)
* [AWS Systems Manager (aka Amazon EC2 Simple Systems Manager (SSM))](https://docs.aws.amazon.com/systems-manager/latest/userguide/what-is-systems-manager.html)
  * [Amazon SSM Agent Source Code Repository](https://github.com/aws/amazon-ssm-agent)
  * [Amazon SSM Session Manager Plugin Source Code Repository](https://github.com/aws/session-manager-plugin)
  * [AWS Systems Manager Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
    * [Start a session](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-sessions-start.html)
      * [Starting a session (AWS CLI)](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-sessions-start.html#sessions-start-cli)
      * [Starting a session (SSH)](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-sessions-start.html#sessions-start-ssh)
        * [Allow and control permissions for SSH connections through Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-getting-started-enable-ssh-connections.html)
      * [Starting a session (port forwarding)](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-sessions-start.html#sessions-start-port-forwarding)
* IPv6
  * [IPv6 on AWS](https://docs.aws.amazon.com/whitepapers/latest/ipv6-on-aws/IPv6-on-AWS.html)
  * [IPv6 support for your VPC](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-migrate-ipv6.html)
  * [AWS and IPv6](https://www.youtube.com/watch?v=bJK5R_dJCBY)
  * [Architect and build IPv6 networks on AWS](https://www.youtube.com/watch?v=zRILaf5JeTM)

# Alternatives

* https://github.com/terraform-aws-modules
