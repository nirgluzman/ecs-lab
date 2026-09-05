# ECS Lab

A personal sandbox where I experiment with [**Amazon ECS**](https://aws.amazon.com/ecs/) concepts - clusters, task definitions, services, capacity providers (Fargate; EC2 out of scope for now), networking, IAM roles, service discovery, autoscaling, and logging.

All infrastructure is provisioned with **Terraform**. Nothing is created by hand in the console, so every experiment is reproducible and disposable.

Two top-level directories:

```
terraform/   # the AWS infrastructure - VPC, ECS cluster, Fargate services
services/    # the workload - the containers that run on it
scripts/     # small operator helpers, e.g. publishing the CI role to GitHub
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
├── variables.tf         # shared inputs - naming, network, ECR, MongoDB, app services
├── secrets.auto.tfvars.example  # password template - copy to secrets.auto.tfvars
├── network.tf           # custom VPC, IGW, one public subnet per AZ, routing
├── cluster.tf           # the shared ECS cluster
├── ecr.tf               # one private image repository per service
├── ssm.tf               # service configuration and credentials in Parameter Store
├── namespaces.tf        # two Cloud Map namespaces for Service Connect
├── service-nginx.tf     # nginx at the edge - a standalone experiment
├── service-frontend.tf  # Streamlit, internet-facing
├── service-backend.tf   # FastAPI, internal
├── service-mongodb.tf   # MongoDB, internal
├── github-oidc.tf       # GitHub Actions OIDC provider, CI role, push + deploy policies
├── outputs.tf           # VPC and subnet IDs, service names, registry and parameter ARNs
└── modules/
    └── service/         # one Fargate service, instantiated once per microservice
        ├── versions.tf
        ├── variables.tf # the interface - image, port, secrets, discovery, sizing, exposure
        ├── main.tf      # log group, security group, task definition, service, Service Connect
        ├── iam.tf       # per-service execution and task roles
        └── outputs.tf   # security group ID, role names, log group, task definition ARN
```

**What it builds:** a VPC with a public subnet in each of two AZs, an ECS cluster,
one private ECR repository per service, the service configuration in Parameter
Store, two Cloud Map namespaces, and four Fargate services - nginx on its own,
plus the frontend, backend and mongodb of the application stack. No NAT gateway
and no load balancer - tasks reach the internet through the IGW and are reached
directly on their own public IP.

**Why a `service` module:** the goal is several microservices sharing one VPC and
one cluster. Each has the same shape - task definition, log group, security group,
its own IAM roles - and differs only in image, port, sizing, exposure, secrets,
health check and discovery. The VPC, the cluster and the namespaces stay in the root because
each exists exactly once.

### Image registry

`ecr.tf` creates one private repository per entry in `ecr_repositories`, named
`<name_prefix>/<service>`. The resulting image URI - `<account>.dkr.ecr.<region>.amazonaws.com/ecslab/backend:<tag>` -
is exactly the `<IMAGE_PREFIX>/<service>:<IMAGE_TAG>` shape Compose already
builds, so the same build pushes to ECR with no re-tagging:

```bash
export IMAGE_PREFIX=$(terraform -chdir=terraform output -raw ecr_registry)
```

Tags are immutable, because a moved tag is a rollback that silently does
nothing - ECS resolves a task definition to a digest. The tags the local loop
overwrites (`dev*`, `latest`) are excluded via `ecr_mutable_tag_filters`.
A lifecycle policy expires untagged images after a day and keeps the newest ten
tagged ones, so rebuilds do not accumulate billable layers. Repositories are
`force_delete = true` so `terraform destroy` still leaves nothing behind.

Pulls need no repository policy: the per-service execution role already carries
`AmazonECSTaskExecutionRolePolicy`, and in-account access is settled by that
identity policy alone.

Pushes from CI authenticate through the role in
[CI credentials](#ci-credentials-github-actions-oidc); the workflow that
builds and pushes comes next.

### CI credentials (GitHub Actions OIDC)

`github-oidc.tf` lets GitHub Actions push to ECR **without an access key in the
repository**. The workflow asks GitHub for a short-lived OIDC token describing
itself, STS validates it against the registered identity provider, and hands
back credentials for `ecslab-github-actions`. The only value GitHub stores is
the role ARN.

Two conditions carry the whole trust boundary - without them any repository on
GitHub could assume the role:

| Claim | Condition | Value |
| --- | --- | --- |
| `aud` | StringEquals | `sts.amazonaws.com` |
| `sub` | StringLike | `repo:<github_repository>:ref:refs/heads/<github_default_branch>` |

Set `github_oidc_subjects` to replace that default entirely - to allow tags
(`...:ref:refs/tags/*`) or a deployment environment. The role's inline policy
grants layer upload and `PutImage` on this project's repositories only, plus
`ecr:GetAuthorizationToken`, which has no resource to scope to.

A second inline policy, `ecs-deploy`, covers the other half of the pipeline -
register a new task definition revision, then point the service at it:

| Statement | Actions | Scope |
| --- | --- | --- |
| `RegisterTaskDefinitions` | `ecs:RegisterTaskDefinition`, `ecs:DescribeTaskDefinition`, `ecs:ListTaskDefinitions` | `*` - task definitions are account-level and support no resource-level permissions |
| `PassTaskRoles` | `iam:PassRole` | the execution and task role of each application service, and only when `iam:PassedToService` is `ecs-tasks.amazonaws.com` |
| `UpdateServices` | `ecs:UpdateService`, `ecs:DescribeServices` | the frontend, backend and mongodb service ARNs, conditioned on `ecs:cluster` |
| `InspectCluster` | `ecs:DescribeClusters` | the one cluster |

`PassRole` is where the teeth are. Registering a revision hands ECS the roles
named in it, so a deployer with `iam:PassRole` on `*` can run a task as any
role in the account - which is why the passable ARNs are enumerated. nginx is
not in the list: it runs a public upstream image and is not part of the
pipeline.

No `thumbprint_list`: GitHub is one of the IdPs AWS validates against its own
trusted root CAs, so a pinned fingerprint would be ignored and would rotate out
from under the config. If the account already has a GitHub provider (one per
URL, account-wide), pass its ARN as `github_oidc_provider_arn` instead of
creating a second one.

Publish the ARN to the repository after applying:

```bash
./scripts/set-github-oidc-secret.sh          # or pass owner/repo explicitly
```

That reads the `github_actions_role_arn` output, sets it as the
**`AWS_OIDC_ROLE`** repository secret with `gh`, and dumps every root output to
`terraform/outputs.json` - the registry host, cluster and service names the
deploy workflow needs, in one place. That dump is gitignored: it is a
rebuildable artifact of an apply, and outputs can carry sensitive values.

### Configuration and secrets

`ssm.tf` holds the credentials half of `services/.env.example` in SSM Parameter
Store, under `/ecslab/mongodb/`. `IMAGE_PREFIX` and `IMAGE_TAG` are deliberately
absent - they select which image runs, which is the task definition's job.

One parameter per fact, not per environment variable. The same password is read
by mongodb as `MONGO_INITDB_ROOT_PASSWORD` and by the backend as
`MONGO_PASSWORD`, so a task definition's `secrets` block maps each parameter to
whatever name the container expects:

| Parameter | Type | From `.env` |
| --- | --- | --- |
| `/ecslab/mongodb/root-username` | String | `MONGO_ROOT_USERNAME` |
| `/ecslab/mongodb/root-password` | SecureString | `MONGO_ROOT_PASSWORD` |
| `/ecslab/mongodb/app-username` | String | `MONGO_APP_USERNAME` |
| `/ecslab/mongodb/app-password` | SecureString | `MONGO_APP_PASSWORD` |
| `/ecslab/mongodb/database` | String | `MONGO_DB` |

Usernames stay `String` - knowing the app user is called `app` is not a way in,
and plain parameters are readable without a decrypt call. Passwords are
`SecureString` under the AWS managed key `alias/aws/ssm`, which is why the
execution role needs no `kms:Decrypt`; a customer-managed key would require it.

**Passwords never enter the state file.** They are set through Terraform 1.11's
write-only `value_wo` argument from `ephemeral` variables, so the plaintext goes
to AWS and nowhere else - not `terraform.tfstate`, not a saved plan:

```bash
cd terraform
cp secrets.auto.tfvars.example secrets.auto.tfvars   # gitignored; then edit
terraform apply
```

The cost of that is no drift detection: Terraform cannot compare a value it does
not keep. Bump `mongo_secret_version` to push a changed password.

Fetching these is the **execution role's** job, not the task role's - it reads
them before the container starts. `ssm.tf` creates the read policy for that;
attach it to a service with the module's `execution_role_name` output.

### Namespaces

`namespaces.tf` creates two Cloud Map HTTP namespaces, and `cluster.tf` still
creates exactly one cluster. **A namespace is a discovery boundary, not a
placement boundary** - all four services run in the same cluster, on the same
subnets, but a service can only resolve names inside its own namespace:

```
ecslab-fargate  (one cluster)
├── ecslab-nginx namespace   nginx
└── ecslab-app   namespace   frontend -> backend -> mongodb
```

nginx is the standalone edge experiment and sits alone in `ecslab-nginx`, so it
cannot see the application stack even though it shares every piece of
infrastructure with it.

Inside `ecslab-app`, discovery is **Service Connect**: ECS injects an Envoy
sidecar, and a client connects to `backend:8000` or `mongodb:27017` rather than
to a task IP that changes on every deployment. HTTP namespaces, not private DNS
ones - the names are resolved by the sidecar, so there is no hosted zone to pay
for or clean up. Two knobs on the module control it:

- `namespace_arn` - which namespace to join, `null` to opt out entirely.
- `discoverable` - register a name others can call. The frontend is `false`: it
  joins as a *client*, which is what lets it resolve `backend`, but nothing
  calls it by name.

Security groups are unchanged by any of this. The sidecar still connects to the
target ENI on the container port, so mongodb admits the backend's security
group and the backend admits the frontend's - identity, not IP addresses. Those
are passed as a **map** keyed by a caller-chosen label, not a list: `for_each`
keys must be known at plan time and a security group ID is not.
MongoDB stays on plain TCP; the backend declares `app_protocol = "http"`.

The proxy is not free. It is a second container drawing on the same task-level
`cpu` and `memory`, and AWS asks for 256 extra CPU units and at least 64 MiB to
cover it - so every service in a namespace is sized 512/1024 rather than
the module's 256/512 default.

**Adding a service:** copy `service-nginx.tf` to `service-<name>.tf`. Internal
services stay off the internet and name who may reach them:

```hcl
module "worker" {
  source = "./modules/service"

  name   = "worker"
  image  = "..."
  public = false

  # join the namespace and register "worker" for others to call
  namespace_arn = aws_service_discovery_http_namespace.app.arn
  discoverable  = true

  # tracks the backend's tasks as their IPs churn. A map, not a list: for_each
  # keys must be known at plan time, and a security group ID is not.
  allowed_security_groups = { backend = module.backend.security_group_id }
}
```

### Running the application stack

The three application services default to **`app_desired_count = 0`**: their ECR
repositories are empty until the build and push step exists, and a service
pointed at a missing image fails its deployment. So the stack applies cleanly
today and runs nothing. Once images are pushed:

```bash
terraform apply -var app_desired_count=1
```

`image_tag` (default `dev`) picks the tag, and `app_cpu_architecture` must match
what the build produced - `docker compose build` on an x86 machine emits x86
images, and Fargate will not run those on ARM64.

MongoDB runs with **no volume attached**, so its data lives in the task's
ephemeral storage and disappears when the task is replaced. That is deliberate
for a lab - it also means `/docker-entrypoint-initdb.d` re-runs on every fresh
task, so the application user is always re-created - but an EFS volume is the
prerequisite for keeping anything.

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
- [GitHub CLI](https://cli.github.com/) (`gh auth login`), to publish the CI role ARN as a repository secret
- [uv](https://docs.astral.sh/uv/) (only to run a Python service outside Docker)

## Usage

```bash
cd terraform
cp secrets.auto.tfvars.example secrets.auto.tfvars   # then edit; apply prompts without it
terraform init
terraform plan
terraform apply
# ... experiment ...
terraform destroy
```

The first apply brings up nginx only. The application services are created with
`app_desired_count = 0`, so nothing tries to pull from the still-empty ECR
repositories - see [Running the application stack](#running-the-application-stack).

## Conventions

- State is local for now. Move to an S3 backend with native locking (`use_lockfile = true`) before sharing.
- Secrets never land in the repo: `.env`, `*.tfvars`, `*.tfstate*`,
  `terraform/outputs.json` and `.claude/settings.local.json` are gitignored; `services/.env.example` and
  `terraform/secrets.auto.tfvars.example` are the committed templates.
- The only value GitHub holds is the CI role ARN, as the `AWS_OIDC_ROLE` secret; every AWS credential in CI is minted per run by STS.
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
