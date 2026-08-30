# ECS Lab

A personal sandbox where I experiment with [**Amazon ECS**](https://aws.amazon.com/ecs/) concepts - clusters, task definitions, services, capacity providers (Fargate; EC2 out of scope for now), networking, IAM roles, service discovery, autoscaling, and logging.

All infrastructure is provisioned with **Terraform**. Nothing is created by hand in the console, so every experiment is reproducible and disposable.

## Goals

- Build ECS primitives from scratch, one layer at a time, and see how they interact.
- Keep each experiment cheap and tear-down-able (`terraform destroy` leaves no residue).
- Use the console only to observe, never to configure.

## Prerequisites

- Terraform
- AWS CLI v2, with credentials configured (`aws login` or `aws configure`)
- Docker (for building and pushing lab images to ECR)

## Usage

```bash
terraform init
terraform plan
terraform apply
# ... experiment ...
terraform destroy
```

## Conventions

- State is local for now. Move to a remote backend (S3 + DynamoDB lock) before sharing.
- Secrets never land in the repo: `.env`, `*.tfvars`, `*.tfstate*` and `.claude/settings.local.json` are gitignored.
- Prefer small, single-purpose modules so pieces can be swapped between experiments.

## Development Tooling

The repo ships with Claude Code skills and MCP servers that speed up authoring and reviewing this infrastructure. Shared config (`.claude/settings.json`, `.claude/skills/`, `.mcp.json`) is committed; local secrets are not.

### Skills

| Skill | Purpose | Install |
| --- | --- | --- |
| `aws-core` plugin - 24 skills | AWS service expertise: ECS/Fargate task definitions and services, ECR, VPC/ALB, IAM roles, CloudWatch, IaC | [aws/agent-toolkit-for-aws](https://github.com/aws/agent-toolkit-for-aws) |
| `terraform-skill` | Writing, reviewing and debugging Terraform modules, tests, CI, scans and state ops | [antonbabenko/terraform-skill](https://github.com/antonbabenko/terraform-skill) |

### MCP Servers

| Server | Purpose | Install |
| --- | --- | --- |
| `aws-mcp` | Live AWS API access, docs search and skill retrieval. Bundled with the `aws-core` plugin, not declared in this repo's `.mcp.json` | [aws/agent-toolkit-for-aws](https://github.com/aws/agent-toolkit-for-aws) |
| `terraform` | Terraform Registry lookups - current provider/module versions, resource schemas, module details | [HashiCorp Terraform MCP Server](https://developer.hashicorp.com/terraform/mcp-server) |
| `context7` | Up-to-date library, SDK and CLI documentation, fetched live instead of from model memory | [context7.com](https://context7.com/) |

> **Notes**
>
> - `context7` needs an API key. Put it in `.claude/settings.local.json` (gitignored) - `.mcp.json` only references it as `${CONTEXT7_API_KEY}`:
>
>   ```json
>   { "env": { "CONTEXT7_API_KEY": "ctx7sk-..." } }
>   ```
>
> - `terraform` runs via Docker (`hashicorp/terraform-mcp-server`), so Docker must be running for it to connect.
