#!/usr/bin/env bash
#
# Where is everything right now? Prints one line per running task: its public
# and private IP, the port its container listens on, and a URL when the task's
# security group actually admits the internet.
#
#   ./scripts/service-endpoints.sh                 # every service in the cluster
#   ./scripts/service-endpoints.sh ecslab-frontend # just these
#
# Every task carries a public IP - there is no NAT gateway, so that is how
# image pulls and log delivery leave - but only the services created with
# `public = true` admit 0.0.0.0/0. The rest print "internal": the address is
# real, the port simply will not answer you. That distinction is the reason
# this reads the security group rather than assuming.
#
# Requires: AWS CLI v2 with credentials. No jq - every shape comes from --query.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

command -v aws >/dev/null || { echo "error: aws CLI is not installed" >&2; exit 1; }

# the cluster terraform built, unless one is named in the environment
CLUSTER="${CLUSTER:-$(terraform -chdir="$ROOT/terraform" output -raw cluster_name 2>/dev/null || echo ecslab-fargate)}"

services=("$@")
if [ ${#services[@]} -eq 0 ]; then
  mapfile -t services < <(
    aws ecs list-services --cluster "$CLUSTER" --query 'serviceArns[]' --output text |
      tr '\t' '\n' | sed 's#.*/##' | sort
  )
fi

[ ${#services[@]} -gt 0 ] || { echo "no services in cluster $CLUSTER" >&2; exit 1; }

# describe-task-definition once per family, not once per task
declare -A port_of

printf '%-18s %-9s %-10s %-16s %-16s %s\n' \
  SERVICE STATUS HEALTH "PRIVATE IP" "PUBLIC IP" ENDPOINT
printf '%-18s %-9s %-10s %-16s %-16s %s\n' \
  ------------------ --------- ---------- ---------------- ---------------- --------

for svc in "${services[@]}"; do
  tasks="$(aws ecs list-tasks --cluster "$CLUSTER" --service-name "$svc" \
    --desired-status RUNNING --query 'taskArns' --output text)"

  if [ -z "$tasks" ] || [ "$tasks" = "None" ]; then
    printf '%-18s %s\n' "$svc" "(no running tasks)"
    continue
  fi

  # shellcheck disable=SC2086 # deliberately split: describe-tasks takes a list
  aws ecs describe-tasks --cluster "$CLUSTER" --tasks $tasks --output text \
    --query 'tasks[].[lastStatus,healthStatus,taskDefinitionArn,attachments[?type==`ElasticNetworkInterface`]|[0].details[?name==`networkInterfaceId`]|[0].value]' |
  while IFS=$'\t' read -r status health td eni; do
    # A task still PROVISIONING has no ENI yet. Selecting the attachment by
    # type matters too: with Service Connect the first one is the sidecar,
    # not the network interface.
    eni="${eni%%[[:space:]]*}"
    if [ "${eni#eni-}" = "$eni" ]; then
      printf '%-18s %-9s %-10s %s
' "$svc" "$status" "${health:-NONE}" "(no network interface yet)"
      continue
    fi

    if [ -z "${port_of[$td]:-}" ]; then
      port_of[$td]="$(aws ecs describe-task-definition --task-definition "$td" \
        --query 'taskDefinition.containerDefinitions[0].portMappings[0].containerPort' --output text)"
    fi
    port="${port_of[$td]}"

    # one ENI per task in awsvpc mode; it carries the addresses and the group
    IFS=$'\t' read -r priv pub sg < <(
      aws ec2 describe-network-interfaces --network-interface-ids "$eni" --output text \
        --query 'NetworkInterfaces[0].[PrivateIpAddress,Association.PublicIp,Groups[0].GroupId]'
    )

    endpoint="internal"
    if [ "$pub" != "None" ]; then
      # escaped backticks are JMESPath JSON literals, not command substitution
      open="$(aws ec2 describe-security-group-rules \
        --filters "Name=group-id,Values=$sg" --output text \
        --query "length(SecurityGroupRules[?IsEgress==\`false\` && CidrIpv4=='0.0.0.0/0' && FromPort<=\`$port\` && ToPort>=\`$port\`])")"

      if [ "$open" != "0" ]; then
        case "$port" in
          27017) endpoint="mongodb://$pub:$port" ;;
          *)     endpoint="http://$pub:$port" ;;
        esac
      fi
    fi

    printf '%-18s %-9s %-10s %-16s %-16s %s\n' \
      "$svc" "$status" "${health:-NONE}" "$priv" "$pub" "$endpoint"
  done
done
