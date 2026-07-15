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

`protect_from_scale_in = false` at the ASG level so ECS's managed termination
protection remains the sole, dynamic owner of each instance's protection flag after
launch, rather than competing with a static Terraform-declared default.

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

## State

State is stored locally (`terraform.tfstate`, gitignored). Back it up before making
changes, and consider migrating to a remote backend if this is ever managed from more
than one machine.
