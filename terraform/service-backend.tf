# FastAPI: reachable from the frontend, and the only thing that talks to
# MongoDB. Not internet-facing.

module "backend" {
  source = "./modules/service"

  name        = "backend"
  name_prefix = var.name_prefix
  region      = var.region

  cluster_id = aws_ecs_cluster.fargate.id
  vpc_id     = aws_vpc.this.id
  subnet_ids = [for s in aws_subnet.public : s.id]

  image            = "${aws_ecr_repository.service["backend"].repository_url}:${var.image_tag}"
  container_port   = 8000
  cpu_architecture = var.app_cpu_architecture

  # Sized for two containers, not one: Service Connect injects an Envoy proxy
  # into every task in a namespace, and AWS asks for 256 extra CPU units and at
  # least 64 MiB on its behalf. 256/512 would leave the app sharing a quarter
  # vCPU with it.
  cpu    = 512
  memory = 1024

  # MONGO_HOST is the Service Connect alias, not a task IP: the sidecar resolves it,
  # so a mongodb redeployment does not strand the backend.
  environment = {
    MONGO_HOST = "mongodb"
    MONGO_PORT = "27017"
  }

  # app_config.py reads these by name; the parameters are named for what they
  # are, and the mapping happens here.
  secrets = {
    MONGO_USERNAME    = aws_ssm_parameter.mongo_config["app-username"].arn
    MONGO_PASSWORD    = aws_ssm_parameter.mongo_app_password.arn
    MONGO_DB          = aws_ssm_parameter.mongo_config["database"].arn
    MONGO_AUTH_SOURCE = aws_ssm_parameter.mongo_config["database"].arn
  }

  health_check = {
    command = ["CMD", "python", "-c", "import urllib.request;urllib.request.urlopen('http://localhost:8000/health')"]
  }

  # discoverable as "backend:8000". A REST API really is HTTP, so the proxy is told as much
  # and reports per-request metrics rather than raw connections.
  namespace_arn = aws_service_discovery_http_namespace.app.arn
  discoverable  = true
  app_protocol  = "http"

  public                  = false
  allowed_security_groups = { frontend = module.frontend.security_group_id }

  desired_count = var.app_desired_count

  depends_on = [aws_route_table_association.public]
}

# the execution role fetches the parameters above before uvicorn starts
resource "aws_iam_role_policy_attachment" "backend_parameters" {
  role       = module.backend.execution_role_name
  policy_arn = aws_iam_policy.mongo_parameters_read.arn
}
