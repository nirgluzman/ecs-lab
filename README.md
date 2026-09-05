# ECS Lab

A personal sandbox where I experiment with [**Amazon ECS**](https://aws.amazon.com/ecs/) concepts - clusters, task definitions, services, capacity providers (Fargate; EC2 out of scope for now), networking, IAM roles, service discovery, autoscaling, and logging.

All infrastructure is provisioned with **Terraform**. Nothing is created by hand in the console, so every experiment is reproducible and disposable.

Two top-level directories:

```
terraform/   # the AWS infrastructure - VPC, ECS cluster, Fargate services
services/    # the workload - the containers that run on it
```

## Goals

- Build ECS primitives from scratch, one layer at a time, and see how they interact.
- Keep each experiment cheap and tear-down-able (`terraform destroy` leaves no residue).
- Use the console only to observe, never to configure.

## Infrastructure

A single Terraform root module in `terraform/` - one `init`, one state file, applied as a unit.

```
terraform/
├── versions.tf          # Terraform and AWS provider version constraints
├── providers.tf         # AWS provider: region and default tags
├── variables.tf         # shared inputs - region, name prefix, VPC CIDR, AZ count
├── network.tf           # custom VPC, IGW, one public subnet per AZ, routing
├── cluster.tf           # the shared ECS cluster
├── service-proxy.tf     # nginx at the edge - a module "service" call
├── outputs.tf           # VPC and subnet IDs, cluster and service names
└── modules/
    └── service/         # one Fargate service, instantiated once per microservice
        ├── versions.tf
        ├── variables.tf # the interface - image, port, sizing, exposure
        ├── main.tf      # log group, security group, task definition, service
        ├── iam.tf       # per-service execution and task roles
        └── outputs.tf   # security group ID, task role name, log group
```

**What it builds:** a VPC with a public subnet in each of two AZs, an ECS cluster,
and one Fargate service running nginx at the edge. No NAT gateway and no load
balancer - tasks reach the internet through the IGW and are reached directly on
their own public IP.

**Why a `service` module:** the goal is several microservices sharing one VPC and
one cluster. Each has the same shape - task definition, log group, security group,
its own IAM roles - and differs only in image, port, sizing and exposure. The VPC
and the cluster stay in the root because each exists exactly once.

**Adding a service:** copy `service-proxy.tf` to `service-<name>.tf`. Internal
services stay off the internet and name who may reach them:

```hcl
module "backend" {
  source = "./modules/service"

  name   = "backend"
  image  = "..."
  public = false

  # tracks the proxy's tasks as their IPs churn
  allowed_security_group_ids = [module.proxy.security_group_id]
}
```

## Services

The workload lives in `services/` - three containers wired together by one
compose file, so the whole stack can be exercised locally before any of it
reaches ECS.

```
frontend (Streamlit :8501)  ->  backend (FastAPI :8000)  ->  mongodb (:27017)
```

```
services/
├── docker-compose.yml   # the local stack: build, env, healthchecks, dependencies
├── .env.example         # image + credential template - copy to .env
├── frontend/            # Streamlit UI
├── backend/             # FastAPI CRUD API over an `items` collection
└── mongodb/             # mongo:8.0 + init script
```

Each service is self-contained - its own `Dockerfile`, its own dependencies, its
own README. Python dependencies are managed with **uv**; both `uv.lock` files are
committed and the images build with `--locked`, so a build either reproduces the
exact pinned set or fails.

**Run it locally:**

```bash
cd services
cp .env.example .env     # then edit the passwords
docker compose up --build
```

Then <http://localhost:8501> for the UI and <http://localhost:8000/docs> for the API.

**Why it is shaped this way:** the stack exists to give the ECS work something
real to deploy, so every choice mirrors what the task definitions will need.
Configuration is environment variables only, so the same names come from `.env`
locally and from **SSM Parameter Store** in AWS, with no code change. Compose
builds `<IMAGE_PREFIX>/<service>:<IMAGE_TAG>`, an ECR image URI, so pointing
`IMAGE_PREFIX` at the registry pushes the same build to ECR untouched. The backend
authenticates as a least-privileged MongoDB user created on first start, never
root. Both images run as a non-root user. Startup is ordered by health rather
than luck, and those same health checks become ECS container health checks.

See `services/README.md` for the development loop and per-service detail.

## Prerequisites

- Terraform
- AWS CLI v2, with credentials configured (`aws login` or `aws configure`)
- Docker with Compose (runs the local stack; builds and pushes images to ECR)
- [uv](https://docs.astral.sh/uv/) (only to run a Python service outside Docker)

## Usage

```bash
cd terraform
terraform init
terraform plan
terraform apply
# ... experiment ...
terraform destroy
```

## Conventions

- State is local for now. Move to an S3 backend with native locking (`use_lockfile = true`) before sharing.
- Secrets never land in the repo: `.env`, `*.tfvars`, `*.tfstate*` and `.claude/settings.local.json` are gitignored; `services/.env.example` is the committed template.
- Shared infrastructure lives in the root; anything instantiated more than once
  becomes a module.
- One service per `service-*.tf` file, so call sites group together in a listing.
- One folder per service under `services/`, each owning its Dockerfile,
  dependencies and README, so a service can be built and deployed on its own.

## Development Tooling

The repo ships with Claude Code skills and MCP servers that speed up authoring and reviewing this infrastructure. Shared config (`.claude/settings.json`, `.claude/skills/`, `.mcp.json`) is committed; local secrets are not.

### Skills

| Skill | Purpose | Install |
| --- | --- | --- |
| `aws-core` plugin | AWS service expertise - ECS/Fargate, ECR, VPC/ALB, IAM, CloudWatch | [aws/agent-toolkit-for-aws](https://github.com/aws/agent-toolkit-for-aws) |
| `terraform-skill` | Terraform modules, tests, CI, scans and state ops | [antonbabenko/terraform-skill](https://github.com/antonbabenko/terraform-skill) |

### MCP Servers

| Server | Purpose | Install |
| --- | --- | --- |
| `aws-mcp` | Live AWS API access, docs search and skill retrieval | [aws/agent-toolkit-for-aws](https://github.com/aws/agent-toolkit-for-aws) |
| `terraform` | Registry lookups - provider versions, resource schemas | [HashiCorp Terraform MCP Server](https://developer.hashicorp.com/terraform/mcp-server) |
| `context7` | Library, SDK and CLI docs fetched live, not from memory | [context7.com](https://context7.com/) |

> **Notes**
>
> - `aws-mcp` ships with the `aws-core` plugin, so it is not declared in this repo's `.mcp.json`.
>
> - `context7` needs an API key. Put it in `.claude/settings.local.json` (gitignored) - `.mcp.json` only references it as `${CONTEXT7_API_KEY}`:
>
>   ```json
>   { "env": { "CONTEXT7_API_KEY": "ctx7sk-..." } }
>   ```
>
> - `terraform` runs via Docker (`hashicorp/terraform-mcp-server`), so Docker must be running for it to connect.
