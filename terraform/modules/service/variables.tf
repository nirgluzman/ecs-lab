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

variable "command" {
  description = "overrides the image CMD when set"
  type        = list(string)
  default     = null
}

# --- sizing -----------------------------------------------------------------

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

# --- exposure ---------------------------------------------------------------

variable "public" {
  description = "open container_port to 0.0.0.0/0; false leaves the service reachable only from allowed_security_group_ids"
  type        = bool
  default     = false
}

variable "allowed_security_group_ids" {
  description = "security groups permitted to reach container_port, for service-to-service traffic"
  type        = list(string)
  default     = []
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
