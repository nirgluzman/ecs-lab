# --- identity ---------------------------------------------------------------

variable "name" {
  description = "service name, unique within the cluster"
  type        = string
}

variable "name_prefix" {
  description = "prefix shared by every resource in the stack"
  type        = string
}

# --- placement, supplied by the root module ---------------------------------

variable "cluster_id" {
  description = "ARN of the ECS cluster to run in"
  type        = string
}

variable "vpc_id" {
  description = "VPC the task security group belongs to"
  type        = string
}

variable "subnet_ids" {
  description = "subnets the tasks may run in; their AZs decide task placement"
  type        = list(string)
}

variable "region" {
  description = "region, used for the awslogs driver"
  type        = string
}

# --- container --------------------------------------------------------------

variable "image" {
  description = "container image to run"
  type        = string
}

variable "container_port" {
  description = "port the container listens on"
  type        = number
  default     = 80
}

variable "environment" {
  description = "plain environment variables passed to the container"
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "environment variables sourced from SSM or Secrets Manager: env var name -> parameter ARN"
  type        = map(string)
  default     = {}
}

variable "app_protocol" {
  description = "protocol hint for Service Connect: \"http\", \"http2\", \"grpc\", or null for plain TCP"
  type        = string
  default     = null

  validation {
    condition     = var.app_protocol == null || contains(["http", "http2", "grpc"], coalesce(var.app_protocol, "http"))
    error_message = "app_protocol must be http, http2, grpc, or null"
  }
}

variable "health_check" {
  description = "container health check; null leaves the task healthy as long as the process is alive"
  type = object({
    command      = list(string)
    interval     = optional(number, 10)
    timeout      = optional(number, 5)
    retries      = optional(number, 5)
    start_period = optional(number, 20)
  })
  default = null
}

variable "command" {
  description = "overrides the image CMD when set"
  type        = list(string)
  default     = null
}

# --- sizing -----------------------------------------------------------------

# A task in a Service Connect namespace runs an injected Envoy proxy alongside
# the app container, and it draws from these same task-level totals. AWS asks
# for 256 extra CPU units and at least 64 MiB to cover it, so the defaults below
# only suit a service with namespace_arn = null.
variable "cpu" {
  description = "task CPU units, must pair with memory per Fargate rules"
  type        = number
  default     = 256
}

variable "memory" {
  description = "task memory in MiB, must pair with cpu per Fargate rules"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "number of tasks to keep running"
  type        = number
  default     = 1
}

variable "cpu_architecture" {
  description = "task CPU architecture"
  type        = string
  default     = "ARM64"

  validation {
    condition     = contains(["ARM64", "X86_64"], var.cpu_architecture)
    error_message = "cpu_architecture must be ARM64 or X86_64"
  }
}

# --- discovery --------------------------------------------------------------

variable "namespace_arn" {
  description = "Cloud Map namespace to join for Service Connect; null disables it entirely"
  type        = string
  default     = null
}

variable "discoverable" {
  description = "register a client alias so others may reach this service by name; false joins the namespace as a client only"
  type        = bool
  default     = false
}

# --- exposure ---------------------------------------------------------------

variable "public" {
  description = "open container_port to 0.0.0.0/0; false leaves the service reachable only from allowed_security_groups"
  type        = bool
  default     = false
}

# A map, not a list, because for_each keys must be known at plan time and a
# security group ID is not - the group is created by the same apply. Keys are
# caller-chosen labels, so the set of rules is static and only the IDs inside
# them resolve during apply.
variable "allowed_security_groups" {
  description = "security groups permitted to reach container_port: caller-chosen label -> security group ID"
  type        = map(string)
  default     = {}
}

variable "assign_public_ip" {
  description = "required while there is no NAT gateway, even for internal services: image pulls and log delivery go out through the IGW"
  type        = bool
  default     = true
}

# --- logging ----------------------------------------------------------------

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 1
}
