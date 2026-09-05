output "vpc_id" {
  description = "ID of the custom VPC"
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = [for s in aws_subnet.public : s.id]
}

output "cluster_name" {
  description = "name of the ECS cluster"
  value       = aws_ecs_cluster.fargate.name
}

output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.fargate.arn
}

output "service_names" {
  description = "ECS service names, by Cloud Map namespace"
  value = {
    (aws_service_discovery_http_namespace.nginx.name) = [module.nginx.service_name]
    (aws_service_discovery_http_namespace.app.name) = [
      module.frontend.service_name,
      module.backend.service_name,
      module.mongodb.service_name,
    ]
  }
}

output "ecr_registry" {
  description = "registry host plus namespace; use as IMAGE_PREFIX when building and pushing"
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.name_prefix}"
}

output "ecr_repository_urls" {
  description = "repository URL per service, the image URI without the tag"
  value       = { for k, r in aws_ecr_repository.service : k => r.repository_url }
}

output "mongo_parameter_arns" {
  description = "SSM parameter ARNs, for the valueFrom of a task definition secrets block"
  value = merge(
    { for k, p in aws_ssm_parameter.mongo_config : k => p.arn },
    {
      "root-password" = aws_ssm_parameter.mongo_root_password.arn
      "app-password"  = aws_ssm_parameter.mongo_app_password.arn
    },
  )
}

output "mongo_parameters_read_policy_arn" {
  description = "attach to a service execution role so it may fetch the mongodb parameters"
  value       = aws_iam_policy.mongo_parameters_read.arn
}
