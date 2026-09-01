# nginx at the edge: the only internet-facing service.
# Backend services will be added as further module "service" blocks with public = false, reachable only
# by passing module.proxy.security_group_id to allowed_security_group_ids.

module "proxy" {
  source = "./modules/service"

  name        = "proxy"
  name_prefix = var.name_prefix
  region      = var.region

  cluster_id = aws_ecs_cluster.fargate.id
  vpc_id     = aws_vpc.this.id
  subnet_ids = [for s in aws_subnet.public : s.id]

  image          = "public.ecr.aws/nginx/nginx:trixie-perl"
  container_port = 80

  public        = true
  desired_count = 1

  # the route to the IGW must exist before the first image pull
  depends_on = [aws_route_table_association.public]
}
