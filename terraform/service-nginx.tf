# nginx at the edge: the standalone experiment, and the only service in the
# ecslab-nginx namespace. It shares the cluster, the VPC and the subnets with
# the application stack but cannot resolve any of it - a namespace is a
# discovery boundary, not a placement one.

module "nginx" {
  source = "./modules/service"

  name        = "nginx"
  name_prefix = var.name_prefix
  region      = var.region

  cluster_id = aws_ecs_cluster.fargate.id
  vpc_id     = aws_vpc.this.id
  subnet_ids = [for s in aws_subnet.public : s.id]

  image          = "public.ecr.aws/nginx/nginx:trixie-perl"
  container_port = 80

  namespace_arn = aws_service_discovery_http_namespace.nginx.arn

  # nginx itself is idle, but joining a namespace still buys an Envoy proxy in
  # the task, and AWS budgets 256 CPU units and at least 64 MiB for it.
  cpu    = 512
  memory = 1024

  public        = true
  desired_count = 1

  # the route to the IGW must exist before the first image pull
  depends_on = [aws_route_table_association.public]
}

# --- task permissions -------------------------------------------------------
#
# The task role is created inside the module; policies attach to it from here by name.
# Keeping them at the call site means each service grants only what it needs,
# instead of every service inheriting one shared policy.
#
# nginx calls no AWS API, so this stays commented out. Uncomment and edit when a service needs one.
# Secrets injected through the task definition are fetched by the execution role, not the task role
# (see service-backend.tf for a live example).

# data "aws_iam_policy_document" "nginx_s3" {
#   statement {
#     actions = ["s3:GetObject"]
#     resources = ["arn:aws:s3:::my-bucket/*"]
#   }
# }
#
# resource "aws_iam_role_policy" "nginx_s3" {
#   name   = "s3-read"
#   role   = module.nginx.task_role_name
#   policy = data.aws_iam_policy_document.nginx_s3.json
# }
