#!/usr/bin/env bash
#
# Publish the Terraform-created CI role ARN to GitHub as the AWS_OIDC_ROLE
# repository secret - the only value the workflow needs to reach AWS.
#
# The ARN is not itself a credential - assuming the role still requires an OIDC
# token whose `sub` matches the trust policy - but it is stored as a secret
# rather than a variable so the account ID stays out of public logs.
#
#   ./scripts/set-github-oidc-secret.sh [owner/repo]
#
# Also dumps every root output to terraform/outputs.json - the registry host,
# cluster and service names the deploy workflow needs, in one readable place.
# That file is gitignored: outputs can carry sensitive values, and it is a
# rebuildable artifact of an apply, not source.
#
# Requires: terraform, gh (authenticated: `gh auth login`), an applied state.

set -euo pipefail

SECRET_NAME="AWS_OIDC_ROLE"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT/terraform"
OUTPUTS_FILE="$TF_DIR/outputs.json"

command -v terraform >/dev/null || { echo "error: terraform is not installed" >&2; exit 1; }

# The dump comes first and depends on nothing but Terraform, so a missing or
# unauthenticated gh still leaves a usable outputs.json behind.
# Written via a temp file, so a failed run keeps the previous dump intact.
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
terraform -chdir="$TF_DIR" output -json >"$TMP"
mv "$TMP" "$OUTPUTS_FILE"
echo "wrote $OUTPUTS_FILE"

ROLE_ARN="$(terraform -chdir="$TF_DIR" output -raw github_actions_role_arn)"
[ -n "$ROLE_ARN" ] || { echo "error: github_actions_role_arn is empty - run terraform apply first" >&2; exit 1; }

command -v gh >/dev/null || { echo "error: gh is not installed" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "error: not logged in - run 'gh auth login'" >&2; exit 1; }

# argument wins; otherwise take the repository this checkout points at
REPO="${1:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"

# --body, never --body-file or a heredoc: the value never touches disk
gh secret set "$SECRET_NAME" --repo "$REPO" --body "$ROLE_ARN"

echo "set $SECRET_NAME on $REPO -> $ROLE_ARN"
