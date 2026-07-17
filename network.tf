# Data sources only - the default VPC, its subnets, and the SSH key pair
# already exist in the account and are not managed (created/destroyed) here.

data "aws_vpc" "default" {
  id = "vpc-09a7b8b0c96580f3f"
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_key_pair" "ecs" {
  key_name = var.ssh_key_pair_name
}

data "aws_ssm_parameter" "ecs_optimized_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended"
}

locals {
  ecs_ami_id = jsondecode(data.aws_ssm_parameter.ecs_optimized_ami.value)["image_id"]
}
