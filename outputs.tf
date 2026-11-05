output "cluster_name" {
  description = "Name of the ECS cluster."
  value       = aws_ecs_cluster.this.name
}

output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group backing the ECS cluster."
  value       = aws_autoscaling_group.ecs_instances.name
}

output "capacity_provider_name" {
  description = "Name of the ECS capacity provider."
  value       = aws_ecs_capacity_provider.this.name
}

output "custom_termination_lambda_arn" {
  description = "ARN of the Lambda used as the ASG's custom termination policy."
  value       = aws_lambda_function.custom_ec2_termination.arn
}

output "prometheus_iam_user_name" {
  description = "Name of the IAM user for Prometheus EC2 scraping."
  value       = aws_iam_user.prometheus.name
}

output "graviton_playground_ecr_uri" {
  description = "URI of the Graviton playground ECR repository."
  value       = aws_ecr_repository.graviton_playground.repository_url
}

output "graviton_runner_instance_id" {
  description = "Instance id of the Graviton runner (aws ssm start-session --target <id>)."
  value       = aws_instance.graviton_runner.id
}

output "graviton_runner_token_parameter" {
  description = "SSM parameter the Graviton runner reads its registration token from on first boot."
  value       = aws_ssm_parameter.graviton_runner_token.name
}
