resource "aws_security_group" "ecs_instances" {
  name        = "ecs-instances-default-cluster"
  description = "Allows SSH access"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = ""
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
