# These resources were originally created by hand via the AWS CLI, then
# adopted here rather than being recreated under new names. These import
# blocks are a safety net, not just a one-time migration step: if local state
# is ever lost, `tofu apply` re-adopts the existing AWS resources instead of
# erroring on "already exists" or creating duplicates. Once a resource is
# already tracked in state, its import block is a no-op.

import {
  to = aws_iam_role.ecs_instance_role
  id = "ecsInstanceRole"
}

import {
  to = aws_iam_role_policy_attachment.ecs_instance_role
  id = "ecsInstanceRole/arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

import {
  to = aws_iam_role_policy.ecs_hello_world_logs
  id = "ecsInstanceRole:ecs-hello-world-logs"
}

import {
  to = aws_iam_instance_profile.ecs_instance_role
  id = "ecsInstanceRole"
}

import {
  to = aws_security_group.ecs_instances
  id = "sg-0ded6901db793df4f"
}

import {
  to = aws_launch_template.ecs_instances
  id = "lt-0df7a19db01823f50"
}

import {
  to = aws_autoscaling_group.ecs_instances
  id = "milanoid-ecs-asg"
}

import {
  to = aws_ecs_capacity_provider.this
  id = "milanoid-ecs-capacity-provider"
}

import {
  to = aws_ecs_cluster.this
  id = "milanoid-test-cluster"
}

import {
  to = aws_ecs_cluster_capacity_providers.this
  id = "milanoid-test-cluster"
}

import {
  to = aws_cloudwatch_log_group.hello_world
  id = "/ecs/milanoid-hello-world"
}

import {
  to = aws_ecs_task_definition.hello_world
  id = "arn:aws:ecs:eu-central-1:268091806187:task-definition/hello-world:1"
}
