provider "aws" {
  # set the AWS region from variable
  region = var.region

  # apply default tags to all resources
  default_tags {
    tags = {
      Project   = var.name_prefix
      ManagedBy = "terraform"
    }
  }
}
