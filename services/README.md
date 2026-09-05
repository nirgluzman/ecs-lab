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
├── .env.example         # credential template - copy to .env
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
