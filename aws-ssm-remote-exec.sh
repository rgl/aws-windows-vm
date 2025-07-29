#!/usr/bin/env bash
set -euo pipefail

# wait for the ssm agent to be online.
# NB the ssm agent requires access to several aws endpoints. that requires a
#    internet gateway and one of the following: a eip, a nat gateway, or the
#    aws endpoints available as vpc endpoints.
# NB the ssm agent uses the aws endpoints returned by:
#     sudo ssm-cli get-diagnostics \
#       | perl -nle 'print $1 if /([a-z0-9.-]+\.amazonaws\.com)/i' \
#       | sort -u
while [ \
  "$(aws ssm describe-instance-information \
    --filters "Key=InstanceIds,Values=$AWS_SSM_SSH_EXEC_EC2_INSTANCE_ID" \
    --query 'InstanceInformationList[0].PingStatus' \
    --output text)" != "Online" ]; do
  sleep 10
done

# NB we ignore the host key because we are trusting aws ssm.
ssh \
  -T \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o ProxyCommand='aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p' \
  "$AWS_SSM_SSH_EXEC_EC2_INSTANCE_USERNAME@$AWS_SSM_SSH_EXEC_EC2_INSTANCE_ID" \
  <<<"$AWS_SSM_SSH_EXEC_STDIN"
