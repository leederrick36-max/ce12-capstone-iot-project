output "ecr_repository_url" {
  description = "Push device_runner images here (docker build/tag/push target)"
  value       = aws_ecr_repository.device_runner.repository_url
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.device_runner.name
}

output "ecs_task_definition_arn" {
  value = aws_ecs_task_definition.device_runner.arn
}

output "scheduler_name" {
  value = aws_scheduler_schedule.daily_device_runner.name
}
