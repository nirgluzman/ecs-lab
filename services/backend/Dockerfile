# Multi-stage: uv builds the virtualenv, the final image ships without uv.
# Pattern follows astral-sh/uv-docker-example (multistage.Dockerfile).

FROM ghcr.io/astral-sh/uv:python3.12-trixie-slim AS builder

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_NO_DEV=1 \
    UV_PYTHON_DOWNLOADS=0

WORKDIR /app

# Dependencies only, in their own layer: rebuilt only when pyproject/uv.lock change.
# --locked fails the build if uv.lock is out of date, keeping images reproducible.
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --locked --no-install-project


FROM python:3.12-slim-trixie

# Run as a non-root user (ECS task definitions should not run root either).
RUN groupadd --system --gid 999 nonroot \
 && useradd --system --gid 999 --uid 999 --create-home nonroot

WORKDIR /app

COPY --from=builder --chown=nonroot:nonroot /app/.venv /app/.venv
COPY --chown=nonroot:nonroot app ./app

ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1

USER nonroot
EXPOSE 8000

# Production default; compose overrides this with --reload for local work.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
