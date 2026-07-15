resource "aws_cloudwatch_log_group" "hello_world" {
  name = "/ecs/milanoid-hello-world"
}

resource "aws_ecs_task_definition" "hello_world" {
  family                   = "hello-world"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]

  container_definitions = jsonencode([
    {
      name      = "hello-world"
      image     = "hello-world:latest"
      cpu       = 128
      memory    = 128
      essential = true

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.hello_world.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "hello"
        }
      }
    }
  ])
}

# Long-running task for observing scale-in protection in action.
resource "aws_ecs_task_definition" "scale_in_protection_demo" {
  family                   = "scale-in-protection-demo"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]

  container_definitions = jsonencode([
    {
      name      = "scale-in-protection-demo"
      image     = "public.ecr.aws/docker/library/busybox:latest"
      command   = ["sleep", "1800"]
      cpu       = 128
      memory    = 128
      essential = true

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.hello_world.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "sleep-demo"
        }
      }
    }
  ])
}
