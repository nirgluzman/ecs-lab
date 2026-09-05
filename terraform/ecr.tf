# One private ECR repository per service in services/.
#
# Repositories are named "<name_prefix>/<service>", so a full image URI is
# <account>.dkr.ecr.<region>.amazonaws.com/ecslab/backend:<tag> - the same
# "<IMAGE_PREFIX>/<service>:<IMAGE_TAG>" shape docker-compose.yml already builds.
# Pointing IMAGE_PREFIX at the ecr_registry output pushes those builds untouched.
#
# Pulls need no repository policy: the per-service execution role carries
# AmazonECSTaskExecutionRolePolicy, and same-account identity policies are enough.

data "aws_caller_identity" "current" {}

resource "aws_ecr_repository" "service" {
  for_each = toset(var.ecr_repositories)

  name = "${var.name_prefix}/${each.value}"

  # Digests are what ECS actually runs, so a tag that can be moved out from
  # under a task definition is a rollback that silently does nothing.
  # Release tags are frozen; the mutable dev tags below are the deliberate
  # exception, because the local loop rebuilds them on every change.
  image_tag_mutability = "IMMUTABLE_WITH_EXCLUSION"

  dynamic "image_tag_mutability_exclusion_filter" {
    for_each = var.ecr_mutable_tag_filters

    content {
      filter      = image_tag_mutability_exclusion_filter.value
      filter_type = "WILDCARD"
    }
  }

  # basic scanning, free; findings land in the console under the image
  image_scanning_configuration {
    scan_on_push = true
  }

  # a lab must tear down cleanly - without this, destroy fails on any repo
  # that still holds an image
  force_delete = true

  tags = { Name = "${var.name_prefix}/${each.value}" }
}

# Storage is billed per GB, and every rebuild of a mutable tag orphans the
# previous image as untagged. Without this the registry grows forever.
resource "aws_ecr_lifecycle_policy" "service" {
  for_each = aws_ecr_repository.service

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "expire untagged images after ${var.ecr_untagged_retention_days} day(s)"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.ecr_untagged_retention_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "keep only the newest ${var.ecr_image_retention_count} tagged images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"]
          countType      = "imageCountMoreThan"
          countNumber    = var.ecr_image_retention_count
        }
        action = { type = "expire" }
      },
    ]
  })
}
