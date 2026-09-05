# MongoDB: the bottom of the application stack. Reachable only by the backend,
# and only by name inside the app namespace.
#
# NOTE: no volume is attached, so the data directory lives in the task's
# ephemeral storage and is gone the moment the task is replaced. That is
# tolerable here precisely because it is a lab - and it has one convenient side
# effect: /docker-entrypoint-initdb.d only runs on an empty data directory, so
# every fresh task re-creates the application user. Attach an EFS volume before
# any of this data is worth keeping.

module "mongodb" {
  source = "./modules/service"

  name        = "mongodb"
  name_prefix = var.name_prefix
  region      = var.region

  cluster_id = aws_ecs_cluster.fargate.id
  vpc_id     = aws_vpc.this.id
  subnet_ids = [for s in aws_subnet.public : s.id]

  image            = "${aws_ecr_repository.service["mongodb"].repository_url}:${var.image_tag}"
  container_port   = 27017
  cpu_architecture = var.app_cpu_architecture

  # mongod is the memory-hungry one of the three; 256/512 leaves it thrashing.
  # This also absorbs the Service Connect proxy, which AWS sizes at 256 extra
  # CPU units and at least 64 MiB on top of whatever the app needs.
  cpu    = 512
  memory = 1024

  # Consumed by the official entrypoint and by init/01-app-user.js on first
  # start. Parameter names are per fact, so they differ from the env var names.
  secrets = {
    MONGO_INITDB_ROOT_USERNAME = aws_ssm_parameter.mongo_config["root-username"].arn
    MONGO_INITDB_ROOT_PASSWORD = aws_ssm_parameter.mongo_root_password.arn
    MONGO_INITDB_DATABASE      = aws_ssm_parameter.mongo_config["database"].arn
    MONGO_APP_USERNAME         = aws_ssm_parameter.mongo_config["app-username"].arn
    MONGO_APP_PASSWORD         = aws_ssm_parameter.mongo_app_password.arn
  }

  # same check compose uses: ping needs no authentication, it only proves the
  # server is accepting operations
  health_check = {
    command      = ["CMD", "mongosh", "--quiet", "--eval", "db.adminCommand('ping')"]
    start_period = 30
  }

  # discoverable as "mongodb:27017" inside the app namespace. Left on plain TCP:
  # the wire protocol is not HTTP, so the proxy must not try to parse it.
  namespace_arn = aws_service_discovery_http_namespace.app.arn
  discoverable  = true

  # private, and only the backend may open a connection
  public                  = false
  allowed_security_groups = { backend = module.backend.security_group_id }

  desired_count = var.app_desired_count

  depends_on = [aws_route_table_association.public]
}

# the execution role fetches the parameters above before mongod starts
resource "aws_iam_role_policy_attachment" "mongodb_parameters" {
  role       = module.mongodb.execution_role_name
  policy_arn = aws_iam_policy.mongo_parameters_read.arn
}
