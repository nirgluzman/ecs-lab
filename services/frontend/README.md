# frontend

Streamlit UI for the Items API. It holds no state of its own - every action is
an HTTP call to the backend, so the two services deploy independently.

## What it does

- Shows a banner if the backend (or MongoDB behind it) is unreachable.
- **Add item** form -> `POST /items`.
- One expander per item, each with a Save (`PUT /items/{id}`) and Delete
  (`DELETE /items/{id}`) button.

## Layout

```
frontend/
├── Dockerfile      # multi-stage: uv builds the venv, final image has no uv
├── pyproject.toml  # streamlit + requests
├── uv.lock         # pinned resolution, committed; the build uses --locked
└── app.py          # the entire UI
```

## Configuration

| Variable      | Default                 | Notes                                    |
| ------------- | ----------------------- | ---------------------------------------- |
| `BACKEND_URL` | `http://localhost:8000` | compose sets `http://backend:8000`; on ECS the same name is a Service Connect alias, resolved by the injected sidecar |

## Run

With the whole stack (recommended, see `../README.md`):

```bash
docker compose up --build
```

Then open <http://localhost:8501>.

Standalone, against a backend you already have running:

```bash
uv sync
BACKEND_URL=http://localhost:8000 uv run streamlit run app.py
```

## Notes

- The compose file bind-mounts this whole directory onto `/app`, so saving
  `app.py` re-renders the page without a rebuild. It mounts the directory rather
  than the single file because editors that save by rename replace the file's
  inode, which a single-file bind mount would not follow. The virtualenv lives at
  `/opt/venv` in the image so the mount cannot hide it.
- `STREAMLIT_SERVER_HEADLESS=true` and usage stats off are baked into the image;
  both are noise in a container.
- The image runs as the non-root user `nonroot` (uid 999).
