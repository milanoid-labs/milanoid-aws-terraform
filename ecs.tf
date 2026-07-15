resource "aws_launch_template" "ecs_instances" {
  name = "milanoid-ecs-lt"

  image_id      = local.ecs_ami_id
  instance_type = "t3.micro"
  key_name      = data.aws_key_pair.ecs.key_name

  vpc_security_group_ids = [aws_security_group.ecs_instances.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance_role.name
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo ECS_CLUSTER=${aws_ecs_cluster.this.name} >> /etc/ecs/ecs.config
  EOF
  )
}

resource "aws_autoscaling_group" "ecs_instances" {
  name = "milanoid-ecs-asg"

  min_size         = 0
  max_size         = 2
  desired_capacity = var.desired_capacity

  vpc_zone_identifier       = data.aws_subnets.default.ids
  health_check_type         = "EC2"
  health_check_grace_period = 0

  # ECS's CreateCapacityProvider API requires the ASG to already have
  # NewInstancesProtectedFromScaleIn enabled at creation time when
  # managed_termination_protection is ENABLED - a create-time-only check.
  # Company's ASG declares this false, but only after its capacity provider
  # already existed (an in-place ASG update doesn't re-trigger that check);
  # a from-scratch `tofu apply` that creates both in one pass needs `true`
  # here. This only sets the default for newly launched instances - it
  # doesn't re-assert protection onto already-running ones on each apply,
  # so it doesn't fight ECS's own dynamic per-instance control.
  protect_from_scale_in = true

  # Selection happens in the Lambda before termination is attempted: only
  # instances with no RUNNING ECS tasks are ever offered as candidates.
  termination_policies = [aws_lambda_function.custom_ec2_termination.arn]

  launch_template {
    id      = aws_launch_template.ecs_instances.id
    version = "$Latest"
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = "true"
    propagate_at_launch = true
  }

  tag {
    key                 = "Name"
    value               = "milanoid-ecs-asg-instance"
    propagate_at_launch = true
  }
}

resource "aws_ecs_capacity_provider" "this" {
  name = "milanoid-ecs-capacity-provider"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs_instances.arn
    managed_termination_protection = "ENABLED"
    managed_draining               = "ENABLED"

    managed_scaling {
      status                    = "ENABLED"
      target_capacity           = 100
      minimum_scaling_step_size = 1
      maximum_scaling_step_size = 1
      instance_warmup_period    = 300
    }
  }
}

resource "aws_ecs_cluster" "this" {
  name = "milanoid-test-cluster"

  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = [aws_ecs_capacity_provider.this.name]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.this.name
    weight            = 1
    base              = 1
  }
}
