# Self-hosted GitHub Actions runner on AWS Graviton (arm64) for the
# playground workflow (.github/workflows/graviton-playground.yml).
#
# Cost honesty: t4g.small is NOT free for this account (Free Tier for t4g
# applies only to accounts created on/after 2025-07-15). In eu-central-1 it
# costs $0.0192/hr + $0.005/hr public IPv4 + gp3 EBS ~= $18/month if left
# running 24/7. See README "Graviton playground" section for pause/teardown.

# The runner only ever dials OUT (GitHub polling, docker pulls, ECR push).
# Debugging is via SSM Session Manager, so there is no ingress at all.
resource "aws_security_group" "graviton_runner" {
  name        = "graviton-runner"
  description = "Graviton GH runner - egress only, no ingress (SSM for shell)"
  vpc_id      = data.aws_vpc.default.id

  egress {
    description = "Allow all outbound (GitHub, Docker Hub, ECR, SSM)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Project = "graviton-playground" }
}

data "aws_iam_policy_document" "graviton_runner_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "graviton_runner" {
  name               = "graviton-runner"
  assume_role_policy = data.aws_iam_policy_document.graviton_runner_assume_role.json
}

# Shell access via SSM Session Manager without SSH keys or open ports.
resource "aws_iam_role_policy_attachment" "graviton_runner_ssm" {
  role       = aws_iam_role.graviton_runner.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Least-privilege ECR *push* (get-login-password needs GetAuthorizationToken
# on "*" - it is account-level by design; every other action is repo-scoped).
data "aws_iam_policy_document" "graviton_runner_ecr_push" {
  statement {
    sid       = "GetLoginToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "PushPullPlaygroundRepo"
    effect = "Allow"
    actions = [
      "ecr:DescribeRepositories", # the workflow resolves the repo URI with this
      "ecr:DescribeImages",       # the workflow checks the pushed digest with this
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [aws_ecr_repository.graviton_playground.arn]
  }
}

# The bootstrap reads the registration token from SSM and immediately resets
# the parameter to the placeholder, so it can never be reused or read by a job
# later. Scoped to this one parameter; the aws/ssm managed KMS key already
# allows decrypt via SSM for principals in the account.
data "aws_iam_policy_document" "graviton_runner_token" {
  statement {
    sid       = "ReadAndResetRegistrationToken"
    effect    = "Allow"
    actions   = ["ssm:GetParameter", "ssm:PutParameter"]
    resources = [aws_ssm_parameter.graviton_runner_token.arn]
  }
}

resource "aws_iam_role_policy" "graviton_runner_token" {
  name   = "graviton-runner-registration-token"
  role   = aws_iam_role.graviton_runner.name
  policy = data.aws_iam_policy_document.graviton_runner_token.json
}

resource "aws_iam_role_policy" "graviton_runner_ecr_push" {
  name   = "graviton-runner-ecr-push"
  role   = aws_iam_role.graviton_runner.name
  policy = data.aws_iam_policy_document.graviton_runner_ecr_push.json
}

resource "aws_iam_instance_profile" "graviton_runner" {
  name = "graviton-runner"
  role = aws_iam_role.graviton_runner.name
}

# The short-lived runner registration token never passes through Terraform:
# Terraform only creates this parameter with a placeholder, the operator writes
# the real token with `aws ssm put-parameter` (see README), and the bootstrap
# waits for it, consumes it and resets it to the placeholder. So the token is
# never in tfstate, in user_data (readable from IMDS by any job), or in the
# cloud-init log.
locals {
  graviton_runner_token_placeholder = "PENDING"
}

resource "aws_ssm_parameter" "graviton_runner_token" {
  name        = "/graviton-runner/registration-token"
  description = "GitHub runner registration token, consumed and reset by the graviton runner bootstrap."
  type        = "SecureString"
  value       = local.graviton_runner_token_placeholder

  # Written out of band by the operator and reset by the instance.
  lifecycle {
    ignore_changes = [value]
  }

  tags = { Project = "graviton-playground" }
}

# Newest Amazon Linux 2023 arm64 AMI, resolved at plan time via SSM public
# parameters - no hardcoded AMI ids to rot (same pattern as network.tf).
data "aws_ssm_parameter" "al2023_arm64_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

resource "aws_instance" "graviton_runner" {
  ami                    = data.aws_ssm_parameter.al2023_arm64_ami.value
  instance_type          = "t4g.small"                           # Graviton2 arm64, ~$0.0192/hr eu-central-1 - NOT free (account is outside Free Tier)
  subnet_id              = sort(data.aws_subnets.default.ids)[0] # sorted: AWS gives no order guarantee, unsorted could force replacement
  vpc_security_group_ids = [aws_security_group.graviton_runner.id]
  iam_instance_profile   = aws_iam_instance_profile.graviton_runner.name

  # Default VPC subnets are public -> runner reaches GitHub over outbound.
  associate_public_ip_address = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2 only
  }

  # No secrets in here. Cloud-init only runs on first boot, so any change to
  # the rendered script (runner_version, registration URL, bootstrap edits)
  # replaces the instance instead of being silently ignored. Put a fresh token
  # in SSM before applying such a change (README "Graviton playground").
  user_data = templatefile("${path.module}/templates/graviton_runner_user_data.sh", {
    runner_version          = var.runner_version
    github_registration_url = var.github_registration_url
    aws_region              = var.aws_region
    token_parameter_name    = aws_ssm_parameter.graviton_runner_token.name
    token_placeholder       = local.graviton_runner_token_placeholder
  })
  user_data_replace_on_change = true

  root_block_device {
    volume_type = "gp3"
    volume_size = 12 # AMI ships 8; 12 leaves room for docker layers without EBS surprises
  }

  # The AMI parameter tracks "latest"; without this every new AL2023 release
  # would replace the runner on an unrelated apply. Roll the AMI deliberately
  # with `-replace aws_instance.graviton_runner`.
  lifecycle {
    ignore_changes = [ami]
  }

  tags = { Project = "graviton-playground", Name = "graviton-runner" }
}
