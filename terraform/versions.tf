terraform {
  # constrains the Terraform CLI version
  required_version = ">= 1.16"

  # locks the plugin versions used in this configuration
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.62"
    }
  }
}
