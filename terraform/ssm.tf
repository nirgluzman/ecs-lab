# Configuration for the services, held in SSM Parameter Store.
#
# These are the credentials half of services/.env.example. IMAGE_PREFIX and
# IMAGE_TAG are deliberately absent: they select which image runs, which is the
# task definition's job, not the running container's environment.
#
# One parameter per fact, not per environment variable. The same password is
# read by mongodb as MONGO_INITDB_ROOT_PASSWORD and by the backend as
# MONGO_PASSWORD; a task definition's `secrets` block maps a parameter to
# whatever name each container expects, so the parameter is named for what it
# is rather than for one consumer's spelling of it.

locals {
  ssm_prefix = "/${var.name_prefix}/mongodb"

  # Non-secret: knowing the account uses a user called "app" is not a way in.
  # Kept as String so they are readable in the console without a decrypt call.
  mongo_config = {
    "root-username" = var.mongo_root_username
    "app-username"  = var.mongo_app_username
    "database"      = var.mongo_db
  }
}

resource "aws_ssm_parameter" "mongo_config" {
  for_each = local.mongo_config

  name  = "${local.ssm_prefix}/${each.key}"
  type  = "String"
  value = each.value

  description = "mongodb ${replace(each.key, "-", " ")}"
  tags        = { Name = "${local.ssm_prefix}/${each.key}" }
}

# --- secrets ----------------------------------------------------------------
#
# value_wo is a write-only argument: Terraform sends it to AWS and then forgets
# it, so unlike `value` the plaintext never lands in terraform.tfstate. The
# source variables are ephemeral, which keeps them out of state and plan files
# too. Because nothing is stored, Terraform cannot diff these - a write happens
# only when mongo_secret_version changes.
#
# Supply the values in terraform/secrets.auto.tfvars (*.tfvars is gitignored)
# or as TF_VAR_mongo_root_password / TF_VAR_mongo_app_password.
#
# Encrypted with the AWS managed key alias/aws/ssm. That is why the execution
# role below needs no kms:Decrypt - a customer-managed key would require it.

resource "aws_ssm_parameter" "mongo_root_password" {
  name             = "${local.ssm_prefix}/root-password"
  type             = "SecureString"
  value_wo         = var.mongo_root_password
  value_wo_version = var.mongo_secret_version

  description = "mongodb root password"
  tags        = { Name = "${local.ssm_prefix}/root-password" }
}

resource "aws_ssm_parameter" "mongo_app_password" {
  name             = "${local.ssm_prefix}/app-password"
  type             = "SecureString"
  value_wo         = var.mongo_app_password
  value_wo_version = var.mongo_secret_version

  description = "mongodb application user password"
  tags        = { Name = "${local.ssm_prefix}/app-password" }
}

# --- read access ------------------------------------------------------------
#
# The execution role fetches parameters named in a task definition's `secrets`
# block before the container starts, so this attaches to the execution role,
# not the task role. Scoped to this stack's own parameter path.

data "aws_iam_policy_document" "mongo_parameters_read" {
  statement {
    actions   = ["ssm:GetParameters"]
    resources = ["arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter${local.ssm_prefix}/*"]
  }
}

resource "aws_iam_policy" "mongo_parameters_read" {
  name        = "${var.name_prefix}-mongo-parameters-read"
  description = "read the mongodb parameters under ${local.ssm_prefix}"
  policy      = data.aws_iam_policy_document.mongo_parameters_read.json
}

# Attached alongside the module calls that consume these - see the
# aws_iam_role_policy_attachment at the foot of service-backend.tf and
# service-mongodb.tf. The frontend gets no attachment: it reads no parameters.
