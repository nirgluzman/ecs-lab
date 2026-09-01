# ECS cluster

locals {
  cluster_name = "${var.name_prefix}-fargate"
}

# define the ECS cluster
resource "aws_ecs_cluster" "fargate" {
  name = local.cluster_name

  tags = { Name = local.cluster_name }
}
