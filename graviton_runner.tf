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

resource "aws_iam_role_policy" "graviton_runner_ecr_push" {
  name   = "graviton-runner-ecr-push"
  role   = aws_iam_role.graviton_runner.name
  policy = data.aws_iam_policy_document.graviton_runner_ecr_push.json
}

resource "aws_iam_instance_profile" "graviton_runner" {
  name = "graviton-runner"
  role = aws_iam_role.graviton_runner.name
}

# Newest Amazon Linux 2023 arm64 AMI, resolved at plan time via SSM public
# parameters - no hardcoded AMI ids to rot (same pattern as network.tf).
data "aws_ssm_parameter" "al2023_arm64_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

resource "aws_instance" "graviton_runner" {
  ami                    = data.aws_ssm_parameter.al2023_arm64_ami.value
  instance_type          = "t4g.small" # Graviton2 arm64, ~$0.0192/hr eu-central-1 - NOT free (account is outside Free Tier)
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.graviton_runner.id]
  iam_instance_profile   = aws_iam_instance_profile.graviton_runner.name

  # Default VPC subnets are public -> runner reaches GitHub over outbound.
  associate_public_ip_address = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2 only
  }

  user_data = templatefile("${path.module}/templates/graviton_runner_user_data.sh", {
    runner_version    = var.runner_version
    github_repository = var.github_repository
    runner_token      = var.github_runner_registration_token
  })

  root_block_device {
    volume_type = "gp3"
    volume_size = 12 # AMI ships 8; 12 leaves room for docker layers without EBS surprises
  }

  tags = { Project = "graviton-playground", Name = "graviton-runner" }
}
