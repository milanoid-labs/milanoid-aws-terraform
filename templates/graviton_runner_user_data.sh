#!/bin/bash
# Cloud-init, runs ONCE on first boot of the graviton playground runner.
# Rendered by Terraform templatefile(): the ONLY placeholders are
# runner_version, github_registration_url, runner_token (written as dollar-brace
# forms). If you add a bash brace-expansion of a shell variable, escape the
# dollar sign by doubling it ($$ before the brace) or Terraform will try to
# interpolate it.
set -euxo pipefail

# Runner is .NET-based: needs libicu on AL2023 or config.sh aborts.
# AL2023 base AMI already ships AWS CLI v2; only install it if somehow absent
# (the dnf name differs between AL2/AL2023, so never fail the bootstrap on it).
dnf install -y docker git libicu
command -v aws >/dev/null || dnf install -y aws-cli

systemctl enable --now docker
usermod -aG docker ec2-user

# Name the runner after the instance id so re-registered instances are traceable.
METRIC_TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $METRIC_TOKEN" http://169.254.169.254/latest/meta-data/instance-id)

RUNNER_HOME=/opt/actions-runner
mkdir -p "$RUNNER_HOME"
curl -fsSL "https://github.com/actions/runner/releases/download/v${runner_version}/actions-runner-linux-arm64-${runner_version}.tar.gz" \
  -o /tmp/runner.tar.gz
tar xzf /tmp/runner.tar.gz -C "$RUNNER_HOME"
chown -R ec2-user:ec2-user "$RUNNER_HOME"

# NOTE: the registration token is single-use-ish and expires 1h after creation.
# If this block fails ("invalid or expired token"), the instance still boots;
# destroy it and re-apply with a freshly generated token.
cd "$RUNNER_HOME"
sudo -u ec2-user ./config.sh \
  --url "${github_registration_url}" \
  --token "${runner_token}" \
  --labels graviton \
  --name "$INSTANCE_ID" \
  --replace \
  --unattended

cd "$RUNNER_HOME"
# Must run as root WITH an explicit service user: under cloud-init SUDO_USER
# is empty, so "svc.sh install" without a user installs the unit as root.
./svc.sh install ec2-user
./svc.sh start
