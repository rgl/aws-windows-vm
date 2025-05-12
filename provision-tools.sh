#!/bin/bash
set -euxo pipefail

# install dependencies.
sudo apt-get install -y apt-transport-https make unzip jq

# install terraform.
# see https://www.terraform.io/downloads.html
# see https://github.com/hashicorp/terraform/releases
# renovate: datasource=github-releases depName=hashicorp/terraform
terraform_version='1.11.4'
artifact_url="https://releases.hashicorp.com/terraform/$terraform_version/terraform_${terraform_version}_linux_amd64.zip"
artifact_path="/tmp/$(basename $artifact_url)"
wget -qO $artifact_path $artifact_url
sudo unzip -o $artifact_path -d /usr/local/bin
rm $artifact_path
CHECKPOINT_DISABLE=1 terraform version

# install aws cli.
# see https://docs.aws.amazon.com/cli/latest/userguide/getting-started-version.html
# see https://github.com/aws/aws-cli/tags
# see https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html#cliv2-linux-install
# renovate: datasource=github-tags depName=aws/aws-cli
AWS_VERSION='2.27.12'
aws_url="https://awscli.amazonaws.com/awscli-exe-linux-x86_64-${AWS_VERSION}.zip"
t="$(mktemp -q -d --suffix=.aws)"
wget -qO "$t/awscli.zip" "$aws_url"
unzip "$t/awscli.zip" -d "$t"
"$t/aws/install" \
    --bin-dir /usr/local/bin \
    --install-dir /usr/local/aws-cli \
    --update
rm -rf "$t"
aws --version

# install aws cli session manager plugin.
# see https://github.com/aws/session-manager-plugin/releases
# see https://docs.aws.amazon.com/systems-manager/latest/userguide/install-plugin-debian-and-ubuntu.html
# renovate: datasource=github-releases depName=aws/session-manager-plugin
AWS_SESSION_MANAGER_PLUGIN_VERSION='1.2.707.0'
aws_session_manager_plugin_url="https://s3.amazonaws.com/session-manager-downloads/plugin/$AWS_SESSION_MANAGER_PLUGIN_VERSION/ubuntu_64bit/session-manager-plugin.deb"
t="$(mktemp -q -d --suffix=.aws-session-manager-plugin)"
wget -qO "$t/session-manager-plugin.deb" "$aws_session_manager_plugin_url"
sudo dpkg -i "$t/session-manager-plugin.deb"
rm -rf "$t"
session-manager-plugin --version
