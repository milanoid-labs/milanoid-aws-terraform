# milanoid-aws-terraform

OpenTofu code for my personal ECS (EC2 launch type) lab in the `milanoid` AWS account:
an ECS cluster backed by a capacity-provider-managed Auto Scaling Group (managed
scaling, managed draining, managed termination/scale-in protection), plus a
`hello-world` task definition to smoke-test it end to end.

## Prerequisites

- An EC2 key pair named `ecs-milanoid-key` must already exist in the account
  (`aws ec2 create-key-pair --key-name ecs-milanoid-key ...`). Terraform references it
  by name but never creates or destroys it, since the private key material shouldn't
  live in Terraform state.
- AWS credentials for the `milanoid` account, e.g. via `AWS_PROFILE=milanoid`.

## Usage

```sh
export AWS_PROFILE=milanoid
tofu init
tofu plan
tofu apply
```

By default `desired_capacity = 0`, so `tofu apply` costs nothing - it only creates the
cluster, IAM role, security group, launch template, ASG (with 0 instances), capacity
provider, log group, and task definition, none of which bill anything while idle.

To actually launch a container instance and test the cluster:

```sh
tofu apply -var desired_capacity=1
```

Wait for the instance to register (`aws ecs list-container-instances --cluster
milanoid-test-cluster`), then run the smoke-test task:

```sh
aws ecs run-task \
  --cluster milanoid-test-cluster \
  --task-definition hello-world \
  --capacity-provider-strategy capacityProvider=milanoid-ecs-capacity-provider,weight=1
```

Check the result in CloudWatch Logs (log group `/ecs/milanoid-hello-world`) or via
`aws ecs describe-tasks`.

Scale back down (or `tofu destroy`) when done to stop paying:

```sh
tofu apply -var desired_capacity=0
```

## Cost

Idle (`desired_capacity=0`): $0. Running one instance (`t3.micro`, `desired_capacity=1`):
roughly $0.01/hour plus a small EBS gp3 charge. This account is outside the 12-month EC2
Free Tier window, so none of this is actually free - keep desired capacity at 0 between
test sessions.

## Custom EC2 termination policy

The ASG's scale-in candidate selection is delegated to a Lambda
(`custom_ec2_termination.tf` / `custom_ec2_termination/lambda_function.py`), mirroring
the pattern used by the company's `jenkins-nodes` ASGs. AWS Auto Scaling invokes the
Lambda at *selection* time and only ever terminates instances it returns; the function
filters the ECS cluster's container instances down to those with zero `RUNNING` tasks,
so a busy instance is never offered as a termination candidate in the first place. This
is what makes scale-in reliably task-aware, unlike relying solely on ECS's own
`managed_termination_protection` flag together with the ASG's default (non-ECS-aware)
termination policy.

`protect_from_scale_in = true` at the ASG level: `CreateCapacityProvider` requires this
at creation time when `managed_termination_protection` is `ENABLED`, since both
resources are created together in one `tofu apply` here. This only seeds the default
for newly launched instances - ECS's managed termination protection still dynamically
owns each running instance's actual protection flag afterward.

## Max instance lifetime

`max_instance_lifetime` (default `86400`, i.e. 1 day - the lowest non-zero value AWS
allows) proactively replaces an instance once it reaches that age, independent of task
placement: the ASG launches a replacement first, then terminates the old instance
through the normal scale-in path, so the custom termination Lambda and managed
termination protection still apply. The company's `jenkins-nodes` ASGs use the same
mechanism with a 1-week default; set to 1 day here to make age-based replacement cheap
and fast to observe. AWS's actual allowed range is `0` (disabled) or `86400`-`31536000`
seconds.

## Linting

CI runs `tofu fmt`, `tofu init`, `tofu validate`, and `tflint` on every push/PR to `main`
(see `.github/workflows/lint.yml`). To run the same checks locally:

```sh
brew install opentofu tflint   # or your platform's equivalent

tofu fmt -check -recursive     # checks formatting
tofu init -backend=false       # provider plugins only, no state/backend needed
tofu validate                  # checks config validity
tflint                         # static analysis, see .tflint.hcl
```

## Prometheus IAM user

`iam_prometheus_user.tf` creates an IAM user (`prometheus-ec2-scraper`) with the
AWS-managed `AmazonEC2ReadOnlyAccess` policy attached, for use by an external
Prometheus instance's EC2 service discovery (`ec2_sd_config`). Terraform does not
create an access key for this user, so no secret ever touches Terraform state. Create
one manually after applying:

```sh
aws iam create-access-key --user-name prometheus-ec2-scraper
```

and hand the resulting key/secret to Prometheus out of band.

## Graviton playground

`graviton_ecr.tf` + `graviton_runner.tf` stand up one Graviton2 (arm64) `t4g.small`
registered as a **self-hosted GitHub Actions runner** (label `graviton`) at **org scope**
— like the homelab ARC runners it is shared across org repos, no per-repo registration.
plus an ECR repo `graviton-playground`. `.github/workflows/graviton-playground.yml`
(`workflow_dispatch` only) builds a toy nginx image **natively on arm64** (no QEMU) and
pushes it to ECR. The runner has no ingress and no SSH: shell access is
`aws ssm start-session --target $(tofu output graviton_runner_instance_id)` (needs the
Session Manager plugin). It authenticates to ECR via its IAM instance profile — no static
keys.

**Nothing here is free.** `t4g.small` is `$0.0192/hr` in `eu-central-1`, plus `$0.005/hr`
public IPv4 and 12 GiB gp3 EBS: **~$0.60/day, ~$18/month if left running 24/7**. (The
Free Tier for `t4g` applies only to accounts created on/after 2025-07-15; this account
predates that.) ECR itself is nearly free: no per-repo charge, `$0.10/GB-month` storage,
same-region push from the runner is free.

Apply (the org-scoped registration token expires in 1 hour, so generate and apply in one
shot; it is only needed for the **first** apply — `user_data` is in `ignore_changes`):

```sh
RUNNER_TOKEN=$(gh api orgs/milanoid-labs/actions/runners/registration-token -q .token)
tofu apply -var "github_runner_registration_token=$RUNNER_TOKEN"
```

If cloud-init logs "invalid or expired token" (`/var/log/cloud-init-output.log`), the
instance booted but never registered. Because `user_data` is ignored after creation,
re-applying alone changes nothing — replace it deliberately with a fresh token:

```sh
RUNNER_TOKEN=$(gh api orgs/milanoid-labs/actions/runners/registration-token -q .token)
tofu apply -var "github_runner_registration_token=$RUNNER_TOKEN" \
  -replace aws_instance.graviton_runner
```

Pause between sessions (stops compute+IPv4 billing; runner re-registers fine across
reboots):

```sh
aws ec2 stop-instances --instance-ids $(tofu output graviton_runner_instance_id)
```

Full teardown (removes runner, SG, IAM and the ECR repo including all images):

```sh
tofu destroy
```

**Security note:** this repo is **public** and the runner is long-lived, so anyone can
open a PR that adds a workflow targeting the `graviton` label; if such a run is approved
it executes on the runner with its IAM instance-profile permissions. Mitigations: enable
the org setting that blocks self-hosted runners for fork PRs from users without write
access (org Settings → Actions → General → Self-hosted runners), never add
`pull_request` triggers to workflows on this runner, and prefer `workflow_dispatch`
(and later, carefully scoped `push` on `main`) only.

## State

State is stored locally (`terraform.tfstate`, gitignored). Back it up before making
changes, and consider migrating to a remote backend if this is ever managed from more
than one machine.
