variable "aws_region" {
  description = "AWS region the ECS lab runs in."
  type        = string
  default     = "eu-central-1"
}

variable "ssh_key_pair_name" {
  description = "Name of an existing EC2 key pair used to SSH into container instances. Must already exist - Terraform never manages the private key."
  type        = string
  default     = "ecs-milanoid-key"
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH (port 22) into container instances."
  type        = string
  default     = "109.81.174.65/32"
}

variable "desired_capacity" {
  description = "Desired number of EC2 container instances in the ASG. Defaults to 0 so a fresh apply costs nothing until deliberately scaled up."
  type        = number
  default     = 0
}
