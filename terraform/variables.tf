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
