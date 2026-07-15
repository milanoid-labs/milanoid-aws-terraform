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
