# Per-service IAM. Roles are created inside the module so services never share
# permissions - one service's task role cannot be used by another.

data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# assumed by the ECS agent before the container starts
resource "aws_iam_role" "execution" {
  name               = "${local.full_name}-execution"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

# AWS managed policy covering ECR pulls and CloudWatch Logs writes
resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# assumed by the container itself; empty until the app calls an AWS API.
# attach extra policies from the root using the task_role_name output.
resource "aws_iam_role" "task" {
  name               = "${local.full_name}-task"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}
