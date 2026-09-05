# Fargate service: log group, security group, IAM roles (iam.tf), task definition,
# and the service itself.
# Instantiate once per microservice.

locals {
  full_name = "${var.name_prefix}-${var.name}"

  # Service Connect matches a service to a container port by this name, so the
  # portMappings entry and the service block below must agree on it.
  port_name = "${var.name}-${var.container_port}"
}

# --- logging ----------------------------------------------------------------

# the awslogs driver does not create this, so it must exist before a task runs
resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${local.full_name}"
  retention_in_days = var.log_retention_days
}

# --- networking -------------------------------------------------------------

# in awsvpc mode each task gets its own ENI, so this SG applies per task
resource "aws_security_group" "this" {
  # name_prefix, not name: a replacement creates the new SG before destroying
  # the old one, and two SGs cannot share a name
  name_prefix = "${local.full_name}-task-"
  description = "task security group for ${local.full_name}"
  vpc_id      = var.vpc_id

  tags = { Name = "${local.full_name}-task" }
}

# only for internet-facing services
resource "aws_vpc_security_group_ingress_rule" "public" {
  count = var.public ? 1 : 0

  security_group_id = aws_security_group.this.id
  description       = "from anywhere"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = var.container_port
  to_port           = var.container_port
  ip_protocol       = "tcp"
}

# service-to-service: reference the caller's SG, not its IPs, which churn
resource "aws_vpc_security_group_ingress_rule" "from_service" {
  for_each = var.allowed_security_groups

  security_group_id            = aws_security_group.this.id
  description                  = "from ${each.key}"
  referenced_security_group_id = each.value
  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "tcp"
}

# required outbound: image pulls and log delivery leave through the IGW
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  description       = "all outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # "-1" means all protocols
}

# --- task definition --------------------------------------------------------

resource "aws_ecs_task_definition" "this" {
  family                   = local.full_name
  requires_compatibilities = ["FARGATE"] # omit it and the task registers as EC2-only

  # Fargate requires awsvpc; the task gets its own ENI in one of the subnets
  network_mode = "awsvpc"

  # task-level sizing, shared by every container in the definition
  cpu    = var.cpu
  memory = var.memory

  execution_role_arn = aws_iam_role.execution.arn
  task_role_arn      = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  container_definitions = jsonencode([
    {
      name      = var.name
      image     = var.image
      essential = true # the task stops if this container exits

      # null is omitted from the JSON, leaving the image CMD in place
      command = var.command

      # port mapping requires only the container port in awsvpc mode
      portMappings = [
        {
          name          = local.port_name
          containerPort = var.container_port
          protocol      = "tcp"
          # null leaves the Service Connect proxy on plain TCP; "http" buys
          # per-request metrics but assumes the traffic really is HTTP
          appProtocol = var.app_protocol
        }
      ]

      environment = [for k, v in var.environment : { name = k, value = v }]

      # Fetched by the execution role at start-up, so the value never appears
      # in the task definition, the console, or `describe-tasks` output.
      secrets = [for k, v in var.secrets : { name = k, valueFrom = v }]

      # The container reports its own readiness; ECS replaces it when it stops
      # passing. Without one, "running" only means the process has not exited.
      healthCheck = var.health_check == null ? null : {
        command     = var.health_check.command
        interval    = var.health_check.interval
        timeout     = var.health_check.timeout
        retries     = var.health_check.retries
        startPeriod = var.health_check.start_period
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = var.name
        }
      }
    }
  ])
}

# --- service ----------------------------------------------------------------

resource "aws_ecs_service" "this" {
  name            = local.full_name
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count

  # launch type must match the task definition's requires_compatibilities
  launch_type = "FARGATE"

  # without this a bad image retries forever while apply reports success
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.this.id]
    assign_public_ip = var.assign_public_ip
  }

  # Service Connect: ECS injects an Envoy sidecar that resolves the namespace's
  # client aliases, so a client reaches "backend:8000" instead of a task IP that
  # changes on every deployment. Security groups still apply - the sidecar
  # connects to the target ENI on container_port like anything else.
  dynamic "service_connect_configuration" {
    for_each = var.namespace_arn == null ? [] : [1]

    content {
      enabled   = true
      namespace = var.namespace_arn

      # the sidecar is a separate container, so it needs its own stream prefix
      log_configuration {
        log_driver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "service-connect"
        }
      }

      # Present only for services others call. A client-only service still
      # joins the namespace - that is what lets it resolve the aliases - but
      # registers no name of its own.
      dynamic "service" {
        for_each = var.discoverable ? [1] : []

        content {
          port_name      = local.port_name
          discovery_name = var.name

          client_alias {
            dns_name = var.name
            port     = var.container_port
          }
        }
      }
    }
  }

  # Terraform sees no reference to this, but the first image pull needs it
  depends_on = [aws_iam_role_policy_attachment.execution]

  lifecycle {
    # Both of these are set at creation and then owned by whoever deploys.
    #
    # desired_count: the running count belongs to a CI deploy, an operator with
    # `aws ecs update-service --desired-count`, or later an autoscaling target.
    #
    # task_definition: a CI deploy registers its own revision of this family -
    # same definition, new image tag - and points the service at it. Terraform
    # still holds the revision *it* registered, so without this every apply
    # after a deploy would roll the service back to the last image Terraform
    # knew about.
    #
    # The cost is that a Terraform change to the task definition (cpu, memory,
    # a new secret) registers a revision the service does not pick up. Deploy
    # afterwards - CI reads the family's newest revision - or move the service
    # forward once by hand.
    ignore_changes = [desired_count, task_definition]
  }
}
