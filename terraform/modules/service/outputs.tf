output "service_name" {
  description = "name of the ECS service"
  value       = aws_ecs_service.this.name
}

# the deploy target: `aws ecs update-service --service <arn>`
output "service_arn" {
  description = "ARN of the ECS service"
  value       = aws_ecs_service.this.arn
}

# pass this to another service's allowed_security_groups to let it connect
output "security_group_id" {
  description = "ID of the task security group"
  value       = aws_security_group.this.id
}

output "task_definition_arn" {
  description = "ARN of the task definition revision the service runs"
  value       = aws_ecs_task_definition.this.arn
}

output "log_group_name" {
  description = "CloudWatch log group the container writes to"
  value       = aws_cloudwatch_log_group.this.name
}

# attach extra policies from the root as the app needs AWS APIs
output "task_role_name" {
  description = "name of the task role, for attaching application permissions"
  value       = aws_iam_role.task.name
}

# attach parameter- and secret-read policies to this from the root: the
# execution role, not the task role, fetches a task definition's secrets
output "execution_role_name" {
  description = "name of the execution role, for granting access to secrets"
  value       = aws_iam_role.execution.name
}

# a deployer that registers a new task definition revision must be allowed to
# iam:PassRole both of these - grant it on the ARNs, not on "*"
output "execution_role_arn" {
  description = "ARN of the execution role, for a deployer's iam:PassRole"
  value       = aws_iam_role.execution.arn
}

output "task_role_arn" {
  description = "ARN of the task role, for a deployer's iam:PassRole"
  value       = aws_iam_role.task.arn
}
