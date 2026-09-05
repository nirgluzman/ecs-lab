# services

Three services for local testing, wired together by one compose file:

```
frontend (Streamlit :8501)  ->  backend (FastAPI :8000)  ->  mongodb (:27017)
```

Each service is self-contained - its own `Dockerfile`, its own dependencies, its
own README. Python dependencies are managed with **uv** (never `pip install`);
`uv.lock` is committed and the images build with `--locked`, so a build either
reproduces the exact pinned set or fails.

```
services/
├── docker-compose.yml   # the local stack: build, env, healthchecks, dependencies
├── .env.example         # image + credential template - copy to .env
├── frontend/            # Streamlit UI
├── backend/             # FastAPI CRUD API
└── mongodb/             # mongo:8.0 + init script
```

## Quick start

```bash
cd services
cp .env.example .env     # then edit the passwords
docker compose up --build
```

| Service   | URL                             |
| --------- | ------------------------------- |
| Frontend  | <http://localhost:8501>         |
| API docs  | <http://localhost:8000/docs>    |
| Health    | <http://localhost:8000/health>  |
| MongoDB   | `mongodb://localhost:27017` (loopback only) |

Startup is ordered by health, not luck: the backend waits until MongoDB answers
`ping`, and the frontend waits until `/health` is green.

## Development loop

`backend/app/` and `frontend/` are bind-mounted into their containers, so
code changes take effect without a rebuild (uvicorn runs with `--reload`,
Streamlit re-runs on save). Rebuild only when dependencies change:

```bash
docker compose up --build backend
```

Useful commands:

```bash
docker compose logs -f backend     # follow one service
docker compose ps                  # health status of each service
docker compose down                # stop, keep the database volume
docker compose down -v             # stop and wipe the data (re-runs the DB init script)
```

## Images

Compose builds `<IMAGE_PREFIX>/<service>:<IMAGE_TAG>`, which is exactly an ECR
image URI - `<registry>/<repository>:<tag>`:

| Part | Local default | On AWS |
| ---------- | ----------------- | ------------------------------------------ |
| registry | *(none)* | `<account>.dkr.ecr.<region>.amazonaws.com` |
| repository | `ecslab/backend` | same - one ECR repository per service |
| tag | `dev` | a git SHA |

ECR repository names may contain `/`, so `ecslab/backend` is a legal repository
name and only the registry prefix changes between local and AWS. The `ecslab`
half is Terraform's `name_prefix`; keep the two equal or the push targets a
repository that does not exist. Point
`IMAGE_PREFIX` at the registry and the same build pushes straight up, with no
`docker tag` step in between:

```bash
aws ecr get-login-password --region <region> \
  | docker login --username AWS --password-stdin <account>.dkr.ecr.<region>.amazonaws.com

export IMAGE_PREFIX=<account>.dkr.ecr.<region>.amazonaws.com/ecslab
export IMAGE_TAG=$(git rev-parse --short HEAD)
docker compose build && docker compose push
```

Each repository has to exist in ECR first - `docker push` does not create one.

Use an immutable tag for anything ECS pulls. A task definition pinned to a
mutable tag like `dev` will not reliably pick up a new push: ECS re-pulls when
the task definition changes, so the image URI itself has to change.

## Credentials

`services/.env` holds the MongoDB credentials and is gitignored; `.env.example`
is the committed template. Two users are created on first start:

- **root** - superuser, administration only.
- **app** - `readWrite` on the application database only; this is what the
  backend authenticates with.

Compose reads `.env` and passes the values through as environment variables. In
AWS these same variable names are fed from **SSM Parameter Store** into the task
definition, so no application code changes when the secrets move.

## Verify by hand

```bash
curl -s localhost:8000/health
curl -s -X POST localhost:8000/items \
  -H 'content-type: application/json' \
  -d '{"name":"widget","description":"a test item","quantity":3}'
curl -s localhost:8000/items
```
