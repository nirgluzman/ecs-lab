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

output "service_name" {
  description = "name of the ECS service"
  value       = module.proxy.service_name
}
