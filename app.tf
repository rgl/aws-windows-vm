# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity
data "aws_caller_identity" "current" {}

# see aws ec2 describe-images --output text --owners amazon --filters "Name=name,Values=Windows_Server-2025-English-*" --query 'reverse(sort_by(Images, &CreationDate))[].[Name,CreationDate,ImageId]'
# see https://docs.aws.amazon.com/ec2/latest/windows-ami-reference/ec2-windows-ami-version-history.html
# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami
data "aws_ami" "windows" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["Windows_Server-2025-English-Full-Base-*"] # e.g. Windows_Server-2025-English-Full-Base-2025.04.09
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/key_pair
resource "aws_key_pair" "admin" {
  key_name   = "${var.name_prefix}-app-admin"
  public_key = var.admin_ssh_key_data
}

# see https://docs.aws.amazon.com/systems-manager/latest/userguide/documents-schemas-features.html
# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_document
resource "aws_ssm_document" "get_windows_ssh_host_public_keys" {
  name            = "${var.name_prefix}-get-windows-ssh-host-public-keys"
  document_type   = "Command"
  document_format = "YAML"
  content = yamlencode({
    schemaVersion = "2.2"
    description   = "Get the Windows OpenSSH server host public keys"
    parameters    = {}
    mainSteps = [
      {
        name   = "GetWindowsSshHostPublicKeys"
        action = "aws:runPowerShellScript"
        precondition = {
          StringEquals = ["platformType", "Windows"]
        }
        inputs = {
          timeoutSeconds = 60
          runCommand     = [file("get-windows-ssh-host-public-keys.ps1")]
        }
      }
    ]
  })
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_interface
resource "aws_network_interface" "app" {
  subnet_id          = aws_subnet.public_az_a.id
  private_ips        = [local.vpc_public_az_a_subnet_app_ip_address]
  security_groups    = [aws_security_group.app.id]
  ipv6_address_count = 1
  tags = {
    Name = "${var.name_prefix}-app"
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip
resource "aws_eip" "app" {
  domain                    = "vpc"
  associate_with_private_ip = aws_network_interface.app.private_ip
  instance                  = aws_instance.app.id
  depends_on                = [aws_internet_gateway.main]
  tags = {
    Name = "${var.name_prefix}-app"
  }
}

# NB the guest firewall is also configured by provision-firewall.sh.
# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group
resource "aws_security_group" "app" {
  vpc_id      = aws_vpc.example.id
  name        = "app"
  description = "Application"
  tags = {
    Name = "${var.name_prefix}-app"
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule
resource "aws_vpc_security_group_ingress_rule" "app_ssh" {
  security_group_id = aws_security_group.app.id
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 22
  to_port           = 22
  tags = {
    Name = "${var.name_prefix}-app-ssh"
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule
resource "aws_vpc_security_group_ingress_rule" "app_ssh_ipv6" {
  security_group_id = aws_security_group.app.id
  ip_protocol       = "tcp"
  cidr_ipv6         = "::/0"
  from_port         = 22
  to_port           = 22
  tags = {
    Name = "${var.name_prefix}-app-ssh-ipv6"
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule
resource "aws_vpc_security_group_ingress_rule" "app_winrm" {
  security_group_id = aws_security_group.app.id
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 5985
  to_port           = 5985
  tags = {
    Name = "${var.name_prefix}-app-winrm"
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule
resource "aws_vpc_security_group_ingress_rule" "app_winrm_ipv6" {
  security_group_id = aws_security_group.app.id
  ip_protocol       = "tcp"
  cidr_ipv6         = "::/0"
  from_port         = 5985
  to_port           = 5985
  tags = {
    Name = "${var.name_prefix}-app-winrm-ipv6"
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule
resource "aws_vpc_security_group_ingress_rule" "app_rdp" {
  security_group_id = aws_security_group.app.id
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 3389
  to_port           = 3389
  tags = {
    Name = "${var.name_prefix}-app-rdp"
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule
resource "aws_vpc_security_group_ingress_rule" "app_rdp_ipv6" {
  security_group_id = aws_security_group.app.id
  ip_protocol       = "tcp"
  cidr_ipv6         = "::/0"
  from_port         = 3389
  to_port           = 3389
  tags = {
    Name = "${var.name_prefix}-app-rdp-ipv6"
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule
resource "aws_vpc_security_group_ingress_rule" "app_http" {
  security_group_id = aws_security_group.app.id
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  tags = {
    Name = "${var.name_prefix}-app-http"
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule
resource "aws_vpc_security_group_ingress_rule" "app_http_ipv6" {
  security_group_id = aws_security_group.app.id
  ip_protocol       = "tcp"
  cidr_ipv6         = "::/0"
  from_port         = 80
  to_port           = 80
  tags = {
    Name = "${var.name_prefix}-app-http-ipv6"
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule
resource "aws_vpc_security_group_egress_rule" "app_all" {
  security_group_id = aws_security_group.app.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  tags = {
    Name = "${var.name_prefix}-app-all"
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule
resource "aws_vpc_security_group_egress_rule" "app_all_ipv6" {
  security_group_id = aws_security_group.app.id
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"
  tags = {
    Name = "${var.name_prefix}-app-all-ipv6"
  }
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
resource "aws_iam_role" "app" {
  name = "${var.name_prefix}-app"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment
resource "aws_iam_role_policy_attachment" "app" {
  role       = aws_iam_role.app.name
  policy_arn = aws_iam_policy.app.arn
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy
resource "aws_iam_policy" "app" {
  name = "${var.name_prefix}-app"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ssm:GetParameters",
          "ssm:GetParameter",
        ]
        Resource = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/${aws_iam_instance_profile.app.role}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:DescribeParameters"]
        Resource = "*"
      }
    ]
  })
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile
resource "aws_iam_instance_profile" "app" {
  name = "${var.name_prefix}-app"
  role = aws_iam_role.app.name
}

# see https://docs.aws.amazon.com/systems-manager/latest/userguide/ssm-agent.html
# see https://docs.aws.amazon.com/systems-manager/latest/userguide/setup-instance-permissions.html
# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment
resource "aws_iam_role_policy_attachment" "app_ssm_agent" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter
resource "aws_ssm_parameter" "app_message" {
  name  = "/${aws_iam_instance_profile.app.role}/message"
  type  = "String"
  value = "Hello, World!"
}

locals {
  # NB the logs are stored at C:\ProgramData\Amazon\EC2Launch\log\agent.log, which contains the path for this script output, e.g.:
  #      2025-05-13 07:34:41 Info: Script file is created at: C:\Windows\system32\config\systemprofile\AppData\Local\Temp\EC2Launch1320634735\UserScript.ps1
  #      2025-05-13 07:34:41 Info: Error file is created at: C:\Windows\system32\config\systemprofile\AppData\Local\Temp\EC2Launch1320634735\err.tmp
  #      2025-05-13 07:34:41 Info: Output file is created at: C:\Windows\system32\config\systemprofile\AppData\Local\Temp\EC2Launch1320634735\output.tmp
  # see https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html#ec2-windows-user-data
  # see https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2launch-v2-settings.html#ec2launch-v2-task-configuration
  app_user_data = yamlencode({
    version = "1.1"
    # NB even thou this is an array, EC2Launch only executes the first task of
    #    the same type. e.g.: if you have two executeScript tasks, only the
    #    first is executed.
    # NB the executeScript task supports the execution of multiple scripts by
    #    including them on its inputs array.
    tasks = [
      # see https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2launch-v2-task-definitions.html#ec2launch-v2-enableopenssh
      {
        task = "enableOpenSsh"
      },
      # see https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2launch-v2-task-definitions.html#ec2launch-v2-executescript
      {
        task = "executeScript"
        inputs = [
          {
            frequency = "once"
            type      = "powershell"
            runAs     = "localSystem"
            content   = file("provision-winrm.ps1")
          },
          {
            frequency = "once"
            type      = "powershell"
            runAs     = "localSystem"
            content   = file("provision-app.ps1")
          },
        ]
      },
    ]
  })
}

# see https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance
resource "aws_instance" "app" {
  ami                  = data.aws_ami.windows.id
  instance_type        = "t3.medium" # 2 cpu. 4 GiB RAM. Nitro System. see https://aws.amazon.com/ec2/instance-types/t3/
  iam_instance_profile = aws_iam_instance_profile.app.name
  key_name             = aws_key_pair.admin.key_name
  user_data_base64     = base64encode(local.app_user_data)
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
  network_interface {
    network_interface_id = aws_network_interface.app.id
    device_index         = 0
  }
  root_block_device {
    volume_size = 50 # GB. default is 30 GB, which only leaves ~6 GB free, so bump it.
    volume_type = "gp3"
  }
  tags = {
    Name = "example-windows"
  }
}

# see https://developer.hashicorp.com/terraform/language/resources/terraform-data
resource "terraform_data" "app_ready" {
  provisioner "local-exec" {
    interpreter = ["/usr/bin/env", "bash"]
    command     = "./aws-ssm-remote-exec.sh"
    environment = {
      AWS_SSM_SSH_EXEC_EC2_INSTANCE_ID       = aws_instance.app.id
      AWS_SSM_SSH_EXEC_EC2_INSTANCE_USERNAME = "Administrator"
      AWS_SSM_SSH_EXEC_STDIN                 = <<-EOF
        :: NB this is a batch script.
        whoami /all
        ipconfig /all
      EOF
    }
  }
  depends_on = [
    aws_eip.app,
    aws_instance.app,
  ]
}
