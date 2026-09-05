# GitHub Actions -> AWS, without a long-lived access key.
#
# The workflow asks GitHub for a short-lived OIDC token describing itself
# ("repo X, ref refs/heads/main"), STS validates that token against the identity
# provider below, and returns credentials for the role - scoped by the trust
# policy to exactly the repository and refs listed here. Nothing secret is
# stored in the repo: the only value GitHub holds is the role ARN.

# One provider per account, keyed by URL, so a second `terraform apply` in an
# account that already has one would fail with EntityAlreadyExists. Set
# github_oidc_provider_arn to reuse that one instead of creating another.
resource "aws_iam_openid_connect_provider" "github" {
  count = var.github_oidc_provider_arn == null ? 1 : 0

  url = "https://token.actions.githubusercontent.com"

  # the `aud` claim the workflow requests; what aws-actions/configure-aws-credentials sends
  client_id_list = ["sts.amazonaws.com"]

  # No thumbprint_list: GitHub is one of the IdPs AWS validates against its own
  # library of trusted root CAs, so a pinned certificate fingerprint would be
  # retained in config and ignored - and rotate out from under us.

  tags = { Name = "${var.name_prefix}-github-actions" }
}

locals {
  # The services CI is allowed to deploy - the application stack it also builds
  # images for. nginx is deliberately absent: it runs a public upstream image
  # and is not part of the pipeline.
  github_deploy_modules = {
    frontend = module.frontend
    backend  = module.backend
    mongodb  = module.mongodb
  }

  github_oidc_provider_arn = coalesce(
    var.github_oidc_provider_arn,
    one(aws_iam_openid_connect_provider.github[*].arn),
  )

  github_repo_owner = split("/", var.github_repository)[0]
  github_repo_name  = split("/", var.github_repository)[1]

  # GitHub now issues `sub` with GitHub's own numeric IDs appended to the owner
  # and the repository - "repo:owner@110996563/repo@1351712645:ref:..." - so a
  # policy pinning the plain name matches nothing and STS answers "Not
  # authorized to perform sts:AssumeRoleWithWebIdentity". The IDs are what make
  # the claim immutable: deleting the repository and recreating it under the
  # same name produces a different one. `*` when they are not supplied, which
  # scopes by name alone and gives that property up.
  github_oidc_repo = (
    var.github_owner_id != null && var.github_repository_id != null
    ? "repo:${local.github_repo_owner}@${var.github_owner_id}/${local.github_repo_name}@${var.github_repository_id}"
    : "repo:${local.github_repo_owner}@*/${local.github_repo_name}@*"
  )

  # `sub` is the claim that says which workflow is calling. Left unconstrained,
  # any repository on GitHub could assume this role. Both spellings are
  # allowed: tokens issued before GitHub's ID rollout carry the plain name.
  github_oidc_subjects = length(var.github_oidc_subjects) > 0 ? var.github_oidc_subjects : [
    "${local.github_oidc_repo}:ref:refs/heads/${var.github_default_branch}",
    "repo:${var.github_repository}:ref:refs/heads/${var.github_default_branch}",
  ]
}

data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    # audience: rejects a token minted for some other relying party
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # subject: which repository, and which ref inside it. StringLike so a
    # pattern like "repo:owner/repo:ref:refs/tags/*" can cover a release flow.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.github_oidc_subjects
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${var.name_prefix}-github-actions"
  description        = "assumed by GitHub Actions in ${var.github_repository} via OIDC"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json

  # a CI credential should be short-lived; the workflow only needs one build
  max_session_duration = 3600
}

# Push permissions, and only to this project's repositories.
# GetAuthorizationToken is the one call that cannot be resource-scoped - it
# mints the registry login and has no repository to attach to.
data "aws_iam_policy_document" "github_actions_ecr_push" {
  statement {
    sid       = "AuthenticateToRegistry"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "PushImages"

    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      # pulls too: layer reuse across builds, and `docker buildx` cache probes
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeImages",
    ]

    resources = [for r in aws_ecr_repository.service : r.arn]
  }
}

resource "aws_iam_role_policy" "github_actions_ecr_push" {
  name   = "ecr-push"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions_ecr_push.json
}

# Deploy permissions: register a new task definition revision and point the
# service at it - the two calls behind `aws ecs update-service`, or behind
# aws-actions/amazon-ecs-deploy-task-definition.
data "aws_iam_policy_document" "github_actions_ecs_deploy" {
  # Task definitions are account-level: none of these support resource-level
  # permissions, so "*" is the only resource IAM accepts here. The teeth are in
  # PassRole below - a task definition is only dangerous if it can name a role.
  statement {
    sid = "RegisterTaskDefinitions"

    actions = [
      "ecs:RegisterTaskDefinition",
      "ecs:DescribeTaskDefinition",
      "ecs:ListTaskDefinitions",
    ]

    resources = ["*"]
  }

  # Registering a revision hands the execution and task roles to ECS, which IAM
  # treats as a privilege escalation unless the passable roles are enumerated.
  # Scoped to this stack's roles, and only when passed to ECS tasks.
  statement {
    sid     = "PassTaskRoles"
    actions = ["iam:PassRole"]

    resources = concat(
      [for m in local.github_deploy_modules : m.execution_role_arn],
      [for m in local.github_deploy_modules : m.task_role_arn],
    )

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  # The deployment itself, plus the describe calls a workflow polls while it
  # waits for the rollout to reach steady state.
  statement {
    sid = "UpdateServices"

    actions = [
      "ecs:UpdateService",
      "ecs:DescribeServices",
    ]

    resources = [for m in local.github_deploy_modules : m.service_arn]

    # belt and braces: the service ARNs above already name the cluster
    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [aws_ecs_cluster.fargate.arn]
    }
  }

  # a workflow that names the cluster wants to confirm it exists first
  statement {
    sid       = "InspectCluster"
    actions   = ["ecs:DescribeClusters"]
    resources = [aws_ecs_cluster.fargate.arn]
  }
}

resource "aws_iam_role_policy" "github_actions_ecs_deploy" {
  name   = "ecs-deploy"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions_ecs_deploy.json
}
