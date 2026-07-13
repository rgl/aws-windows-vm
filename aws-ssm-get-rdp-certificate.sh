#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

function log {
    local msg="$1"
    echo "$(date -Iseconds) $msg" >&2
}

# NB all command executions (including input and output) are saved in
#    AWS Systems Manager, Run Command, Command history, and cannot be deleted
#    by the user, instead, its automatically deleted after 30 days. longer
#    retention periods are possible (e.g. by sending them to cloudwatch or a
#    s3 bucket).
# see https://docs.aws.amazon.com/systems-manager/latest/userguide/walkthrough-cli.html
# see https://docs.aws.amazon.com/cli/latest/reference/ssm/
# see aws ssm describe-document --name AWS-RunShellScript --query "Document.Parameters[*]"
# see aws ssm list-commands --instance-id i-00000000000000000
# see aws ssm list-command-invocations --details --instance-id i-00000000000000000
function get_rdp_certificate {
    local instance_id="$1"
    local ssm_document_name="AWS-RunPowerShellScript"
    local title="RDP Certificate"

    log "Sending the $title command..."
    local command_id
    command_id="$(aws ssm send-command \
        --instance-ids "$instance_id" \
        --document-name "$ssm_document_name" \
        --parameters '{"commands":["[Convert]::ToBase64String((Get-ChildItem \"Cert:\\LocalMachine\\Remote Desktop\").Export(\"Cert\"))"]}' \
        --query Command.CommandId \
        --output text)"

    # NB we use || true to be able to get the command stderr, stdout, and exit code.
    # NB without it, it will fail with the following error and stop the script:
    #       Waiter CommandExecuted failed: Waiter encountered a terminal failure state: For expression "Status" we matched expected path: "Failed"
    log "Waiting for the $title command ($command_id) to execute..."
    aws ssm wait command-executed \
        --instance-id "$instance_id" \
        --command-id "$command_id" \
        || true

    log "Getting the $title command ($command_id) stderr..."
    aws ssm get-command-invocation \
        --instance-id "$instance_id" \
        --command-id "$command_id" \
        --query StandardErrorContent \
        --output text \
        | awk 'NF { found=1 } found' \
        >&2

    log "Getting the $title command ($command_id) stdout..."
    aws ssm get-command-invocation \
        --instance-id "$instance_id" \
        --command-id "$command_id" \
        --query StandardOutputContent \
        --output text \
        | tail -2 \
        | head -1 \
        | tr -d '\r\n' \
        | base64 -d \
        | openssl x509 -inform der -outform pem

    log "Getting the $title command ($command_id) exit code..."
    local response_code
    response_code="$(aws ssm get-command-invocation \
        --instance-id "$instance_id" \
        --command-id "$command_id" \
        --query ResponseCode \
        --output text)"

    if ! [[ "$response_code" =~ ^[0-9]+$ ]]; then
        response_code=1
    fi

    return "$response_code"
}

instance_id="$1"

get_rdp_certificate "$instance_id"
