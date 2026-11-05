#!/bin/bash
# Cloud-init, runs ONCE on first boot of the graviton playground runner.
# Rendered by Terraform templatefile(): the ONLY placeholders are
# runner_version, github_registration_url, aws_region, token_parameter_name and
# token_placeholder (written as dollar-brace forms). If you add a bash
# brace-expansion of a shell variable, escape the dollar sign by doubling it
# ($$ before the brace) or Terraform will try to interpolate it.
#
# This script contains no secrets: the registration token is read from SSM at
# boot (see graviton_runner.tf), never from user_data.
set -euxo pipefail

# Runner is .NET-based: needs libicu on AL2023 or config.sh aborts.
dnf install -y docker git libicu
# The AL2023 AMI ships AWS CLI v2. It is required below (token fetch), so if
# it is somehow missing, try both package names and let set -e abort if
# neither works.
command -v aws >/dev/null || dnf install -y awscli-2 || dnf install -y aws-cli

systemctl enable --now docker
usermod -aG docker ec2-user

# Name the runner after the instance id so re-registered instances are traceable.
IMDS_TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" http://169.254.169.254/latest/meta-data/instance-id)

RUNNER_HOME=/opt/actions-runner
mkdir -p "$RUNNER_HOME"
curl -fsSL "https://github.com/actions/runner/releases/download/v${runner_version}/actions-runner-linux-arm64-${runner_version}.tar.gz" \
  -o /tmp/runner.tar.gz
tar xzf /tmp/runner.tar.gz -C "$RUNNER_HOME"
chown -R ec2-user:ec2-user "$RUNNER_HOME"

TOKEN_PARAM="${token_parameter_name}"
PLACEHOLDER="${token_placeholder}"
REGION="${aws_region}"

# Tracing off from here until the token is gone, so it never lands in
# /var/log/cloud-init-output.log.
set +x

# Wait up to 60 min for the operator to put a token in SSM
# (README "Graviton playground"). Errors are retried: right after creation the
# instance profile credentials or the IAM policy may not have propagated yet.
RUNNER_TOKEN=""
for attempt in $(seq 1 120); do
  value=$(aws ssm get-parameter --region "$REGION" --name "$TOKEN_PARAM" \
    --with-decryption --query Parameter.Value --output text 2>/dev/null || true)
  if [ -n "$value" ] && [ "$value" != "$PLACEHOLDER" ]; then
    RUNNER_TOKEN="$value"
    break
  fi
  echo "attempt $attempt: no registration token in SSM $TOKEN_PARAM yet, retrying in 30s"
  sleep 30
done
unset value

if [ -z "$RUNNER_TOKEN" ]; then
  echo "No registration token appeared in SSM $TOKEN_PARAM within 60 min." >&2
  echo "Put a fresh token there and run: tofu apply -replace aws_instance.graviton_runner" >&2
  exit 1
fi

# Consume the token: reset the parameter before registering, so no job that
# later runs on this runner (with this instance profile) can read it.
aws ssm put-parameter --region "$REGION" --name "$TOKEN_PARAM" \
  --type SecureString --value "$PLACEHOLDER" --overwrite >/dev/null

# Tokens expire 1h after creation. If config.sh fails ("invalid or expired
# token"), the instance still boots but never registers: put a fresh token in
# SSM and run `tofu apply -replace aws_instance.graviton_runner`
# (a plain re-apply does nothing, cloud-init only runs on first boot).
cd "$RUNNER_HOME"
sudo -u ec2-user ./config.sh \
  --url "${github_registration_url}" \
  --token "$RUNNER_TOKEN" \
  --labels graviton \
  --name "$INSTANCE_ID" \
  --replace \
  --unattended
unset RUNNER_TOKEN
set -x

# Must run as root WITH an explicit service user: under cloud-init SUDO_USER
# is empty, so "svc.sh install" without a user installs the unit as root.
./svc.sh install ec2-user
./svc.sh start
