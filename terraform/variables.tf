# --- identity ---------------------------------------------------------------

variable "region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "prefix applied to every named resource"
  type        = string
  default     = "ecslab"
}

# --- networking -------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"

  # subnets are carved with cidrsubnet(vpc_cidr, 8, n), so anything smaller
  # than /20 produces prefixes AWS rejects (/28 is the smallest subnet)
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && tonumber(split("/", var.vpc_cidr)[1]) <= 20
    error_message = "vpc_cidr must be a valid CIDR of /20 or larger"
  }
}

variable "az_count" {
  description = "number of AZs to spread public subnets across"
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 1 && var.az_count <= 3
    error_message = "az_count must be between 1 and 3"
  }
}

# --- ECR --------------------------------------------------------------------

variable "ecr_repositories" {
  description = "one repository per service directory under services/"
  type        = list(string)
  default     = ["frontend", "backend", "mongodb"]
}

variable "ecr_mutable_tag_filters" {
  description = "wildcard tag patterns exempt from immutability, for tags the local loop overwrites"
  type        = list(string)
  default     = ["dev*", "latest"]

  # AWS caps the exclusion list at 5 filters per repository
  validation {
    condition     = length(var.ecr_mutable_tag_filters) <= 5
    error_message = "at most 5 exclusion filters per repository"
  }
}

variable "ecr_image_retention_count" {
  description = "number of tagged images to keep per repository"
  type        = number
  default     = 10
}

variable "ecr_untagged_retention_days" {
  description = "days an untagged image survives before the lifecycle policy expires it"
  type        = number
  default     = 1
}

# --- MongoDB, stored in SSM Parameter Store ---------------------------------

variable "mongo_db" {
  description = "application database name"
  type        = string
  default     = "appdb"
}

variable "mongo_root_username" {
  description = "database superuser, created on first start; administration only"
  type        = string
  default     = "root"
}

variable "mongo_app_username" {
  description = "least-privileged user the backend connects with"
  type        = string
  default     = "app"
}

# Ephemeral: never written to state or to a plan file, and so never defaulted
# to a placeholder either - a missing password should fail, not ship.
variable "mongo_root_password" {
  description = "password for mongo_root_username; set in secrets.auto.tfvars or TF_VAR_mongo_root_password"
  type        = string
  ephemeral   = true
  sensitive   = true
}

variable "mongo_app_password" {
  description = "password for mongo_app_username; set in secrets.auto.tfvars or TF_VAR_mongo_app_password"
  type        = string
  ephemeral   = true
  sensitive   = true
}

variable "mongo_secret_version" {
  description = "bump to push new password values; write-only values are invisible to the plan, so nothing else triggers a write"
  type        = number
  default     = 1
}

# --- application services ---------------------------------------------------

variable "image_tag" {
  description = "tag the three application services run; must exist in ECR before they can start"
  type        = string
  default     = "dev"
}

variable "app_cpu_architecture" {
  description = "must match what the build produces - docker compose on an x86 machine emits X86_64 images, and Fargate will not run them on ARM64"
  type        = string
  default     = "X86_64"

  validation {
    condition     = contains(["ARM64", "X86_64"], var.app_cpu_architecture)
    error_message = "app_cpu_architecture must be ARM64 or X86_64"
  }
}

# The ECR repositories are empty until the build and push step exists, and a
# service pointed at a missing image fails its deployment. Zero lets the whole
# stack apply cleanly now; raise it once the images are pushed.
variable "app_desired_count" {
  description = "tasks to run for frontend, backend and mongodb"
  type        = number
  default     = 0
}

# --- GitHub Actions (OIDC) --------------------------------------------------

variable "github_repository" {
  description = "repository allowed to assume the CI role, as owner/name"
  type        = string
  default     = "nirgluzman/ecs-lab"

  validation {
    condition     = can(regex("^[^/]+/[^/]+$", var.github_repository))
    error_message = "github_repository must be owner/name"
  }
}

variable "github_default_branch" {
  description = "branch the workflow runs from; the ref the default trust subject pins"
  type        = string
  default     = "main"
}

variable "github_oidc_subjects" {
  description = "override the trust policy sub patterns entirely, e.g. to allow tags or an environment"
  type        = list(string)
  default     = []
}

variable "github_oidc_provider_arn" {
  description = "ARN of an existing GitHub OIDC provider in this account; null creates one"
  type        = string
  default     = null
}
