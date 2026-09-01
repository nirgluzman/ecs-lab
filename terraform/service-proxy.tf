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

# --- task permissions -------------------------------------------------------
#
# The task role is created inside the module; policies attach to it from here by name.
# Keeping them at the call site means each service grants only what it needs,
# instead of every service inheriting one shared policy.
#
# nginx calls no AWS API, so this stays commented out. Uncomment and edit when a service needs one.
# Secrets injected through the task definition are fetched by the execution role, not the task role.

# data "aws_iam_policy_document" "proxy_s3" {
#   statement {
#     actions = ["s3:GetObject"]
#     resources = ["arn:aws:s3:::my-bucket/*"]
#   }
# }
#
# resource "aws_iam_role_policy" "proxy_s3" {
#   name   = "s3-read"
#   role   = module.proxy.task_role_name
#   policy = data.aws_iam_policy_document.proxy_s3.json
# }
