# Fargate service: log group, security group, IAM roles (iam.tf), task definition,
# and the service itself.
# Instantiate once per microservice.

locals {
  full_name = "${var.name_prefix}-${var.name}"
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
  for_each = toset(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.this.id
  description                  = "from ${each.value}"
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
          name          = "${var.name}-${var.container_port}"
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = [for k, v in var.environment : { name = k, value = v }]

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

  # Terraform sees no reference to this, but the first image pull needs it
  depends_on = [aws_iam_role_policy_attachment.execution]
}
