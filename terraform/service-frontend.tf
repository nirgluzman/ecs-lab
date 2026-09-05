# Streamlit: the internet-facing half of the application stack.
#
# It joins the app namespace as a client only - nothing calls it by name, it is
# reached on the task's public IP - but membership is what lets it resolve
# "backend". A client-only service registers no alias of its own.

module "frontend" {
  source = "./modules/service"

  name        = "frontend"
  name_prefix = var.name_prefix
  region      = var.region

  cluster_id = aws_ecs_cluster.fargate.id
  vpc_id     = aws_vpc.this.id
  subnet_ids = [for s in aws_subnet.public : s.id]

  image            = "${aws_ecr_repository.service["frontend"].repository_url}:${var.image_tag}"
  container_port   = 8501
  cpu_architecture = var.app_cpu_architecture

  # Sized for two containers, not one: Service Connect injects an Envoy proxy
  # into every task in a namespace, and AWS asks for 256 extra CPU units and at
  # least 64 MiB on its behalf. 256/512 would leave the app sharing a quarter
  # vCPU with it.
  cpu    = 512
  memory = 1024

  environment = {
    BACKEND_URL = "http://backend:8000"
  }

  namespace_arn = aws_service_discovery_http_namespace.app.arn

  # No alias registered, because a Service Connect alias is only resolvable
  # from inside the namespace and nothing in there ever calls the frontend -
  # traffic arrives from the internet, on the task's public IP. Registering one
  # would put a dead listener in every task in the namespace. Membership is
  # still what lets this task resolve "backend".
  #
  # Flip to true only if something inside the namespace starts calling it - an
  # nginx moved in front of it, say. It does nothing for external access.
  discoverable = false

  # no load balancer yet, so the task's own public IP is the entry point
  public        = true
  desired_count = var.app_desired_count

  depends_on = [aws_route_table_association.public]
}
