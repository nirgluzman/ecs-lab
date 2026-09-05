# mongodb

The stock `mongo:8.0` image from Docker Hub, plus one initialization script.
The version is pinned so a rebuild cannot silently jump a major release.

## Layout

```
mongodb/
├── Dockerfile             # FROM mongo:8.0 + the init script
└── init/
    └── 01-app-user.js     # creates the app user, collection and index
```

## Initialization

Everything in `/docker-entrypoint-initdb.d/` runs **once**, on the first start of
an empty data directory. `01-app-user.js` creates:

- user `MONGO_APP_USERNAME` with `readWrite` on `MONGO_INITDB_DATABASE` only -
  the backend never holds root credentials;
- the `items` collection (no secondary index: every query the API issues is an
  `_id` lookup or an `_id` sort, both served by the default index).

To re-run it, destroy the data volume:

```bash
docker compose down -v && docker compose up --build
```

## Configuration

| Variable                      | Consumed by            | Notes                        |
| ----------------------------- | ---------------------- | ---------------------------- |
| `MONGO_INITDB_ROOT_USERNAME`  | official entrypoint    | superuser, administration only |
| `MONGO_INITDB_ROOT_PASSWORD`  | official entrypoint    |                              |
| `MONGO_INITDB_DATABASE`       | entrypoint + init script | application database name  |
| `MONGO_APP_USERNAME`          | `init/01-app-user.js`  | the user the backend connects with |
| `MONGO_APP_PASSWORD`          | `init/01-app-user.js`  |                              |

Compose maps these from `services/.env` (see `../.env.example`).

## Data and access

Data lives in the named volume `mongo-data`, so it survives `docker compose down`
and is wiped by `docker compose down -v`.

Port `27017` is published for local tooling only:

```bash
# as the app user
docker compose exec mongodb mongosh -u app -p change-me-app --authenticationDatabase appdb appdb
# as root
docker compose exec mongodb mongosh -u root -p change-me-root --authenticationDatabase admin
```

## Notes

- This runs a single, unreplicated node - fine for local testing, not for
  anything that needs transactions or change streams (both require a replica set).
- Authentication is on because root credentials are set; the healthcheck uses
  `db.adminCommand('ping')`, which needs no authentication.
