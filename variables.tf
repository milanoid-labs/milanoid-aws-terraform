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

variable "min_size" {
  description = "Minimum size of the ASG. Defaults to 0. Set equal to desired_capacity to lock the ASG at a fixed size, e.g. to prevent ordinary capacity-based scale-in while testing max_instance_lifetime."
  type        = number
  default     = 0
}

variable "github_registration_url" {
  description = "GitHub URL the runner registers against: org URL shares the runner across all org repos (like the ARC runners); a repo URL scopes it to one repo."
  type        = string
  default     = "https://github.com/milanoid-labs"
}

# One-time runner registration token (expires in 1 hour). Scope must match
# github_registration_url. For the org default generate right before apply:
#   gh api orgs/milanoid-labs/actions/runners/registration-token -q .token
variable "github_runner_registration_token" {
  description = "GitHub Actions runner registration token. Only consumed when the instance is (re)created - user_data is in ignore_changes, so routine applies do not need it. Must be generated within 1h. Never committed."
  type        = string
  default     = null
  sensitive   = true
}

variable "runner_version" {
  description = "actions/runner release to install (https://github.com/actions/runner/releases/latest)."
  type        = string
  default     = "2.338.2"
}

variable "max_instance_lifetime" {
  description = "Maximum instance lifetime in seconds before ASG replaces the instance (0 = disabled). Default 1 day (lowest allowed non-zero value) for fast, cheap testing."
  type        = number
  default     = 86400

  validation {
    condition     = var.max_instance_lifetime == 0 || (var.max_instance_lifetime >= 86400 && var.max_instance_lifetime <= 31536000)
    error_message = "max_instance_lifetime must be 0 (disabled) or between 86400 (1 day) and 31536000 (365 days) seconds."
  }
}
