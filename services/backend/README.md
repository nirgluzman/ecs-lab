# backend

FastAPI service exposing CRUD over a single MongoDB collection (`items`).

## Endpoints

| Method | Path          | Purpose                                   |
| ------ | ------------- | ----------------------------------------- |
| GET    | `/health`     | Liveness + a `ping` against MongoDB (503 if the DB is down) |
| POST   | `/items`      | Create an item, returns `201` with the new `id` |
| GET    | `/items`      | List items, newest first (`?limit=` caps the result) |
| GET    | `/items/{id}` | Fetch one item                            |
| PUT    | `/items/{id}` | Replace the mutable fields of one item    |
| DELETE | `/items/{id}` | Delete one item, returns `204`            |

Interactive docs at <http://localhost:8000/docs>.

An item is `{ id, name, description, quantity }`. MongoDB's `_id` is exposed as
the string `id`; an id that is not a valid ObjectId returns `404`, not `500`.

## Layout

```
backend/
├── Dockerfile        # multi-stage: uv builds the venv, final image has no uv
├── pyproject.toml    # dependencies (no [build-system] -> uv "virtual" project)
├── uv.lock           # pinned resolution, committed; the build uses --locked
└── app/
    ├── config.py     # env-var settings, builds the Mongo connection string
    ├── db.py         # client lifespan, collection dependency, id parsing
    ├── models.py     # pydantic request/response models
    └── main.py       # the routes
```

## Configuration

All settings are environment variables (see `app/config.py`):

| Variable            | Default   | Notes                                     |
| ------------------- | --------- | ----------------------------------------- |
| `MONGO_HOST`        | `mongodb` | compose service name                      |
| `MONGO_PORT`        | `27017`   |                                           |
| `MONGO_USERNAME`    | `app`     | the least-privileged app user             |
| `MONGO_PASSWORD`    | `app`     |                                           |
| `MONGO_DB`          | `appdb`   |                                           |
| `MONGO_AUTH_SOURCE` | `appdb`   | database the app user was created in      |
| `MONGO_URI`         | unset     | full connection string; overrides all of the above |

`MONGO_URI` exists so AWS can hand over one ready-made SecureString from SSM
instead of five separate parameters.

## Run

With the whole stack (recommended, see `../README.md`):

```bash
docker compose up --build
```

Standalone, against a MongoDB you already have running:

```bash
uv sync
MONGO_HOST=localhost MONGO_USERNAME=app MONGO_PASSWORD=... \
  uv run uvicorn app.main:app --reload
```

## Notes

- Uses `pymongo`'s `AsyncMongoClient`; `motor` is deprecated and is not used.
- The client is opened in a FastAPI `lifespan` so one connection pool is shared
  by all requests and drained cleanly on shutdown.
- The image runs as the non-root user `nonroot` (uid 999).
