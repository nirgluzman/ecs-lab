# Multi-stage: uv builds the virtualenv, the final image ships without uv.

FROM ghcr.io/astral-sh/uv:python3.12-trixie-slim AS builder

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_NO_DEV=1 \
    UV_PYTHON_DOWNLOADS=0

WORKDIR /app

# Build the venv where it will finally live. A venv bakes absolute paths into
# its shebangs, so copying it to a different prefix would break every entry point.
ENV UV_PROJECT_ENVIRONMENT=/opt/venv

# Dependency layer, keyed on pyproject.toml + uv.lock only.
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --locked --no-install-project


FROM python:3.12-slim-trixie

RUN groupadd --system --gid 999 nonroot \
 && useradd --system --gid 999 --uid 999 --create-home nonroot

WORKDIR /app

# The venv lives outside /app so compose can bind-mount the source over /app
# without hiding it.
COPY --from=builder --chown=nonroot:nonroot /opt/venv /opt/venv
COPY --chown=nonroot:nonroot app.py ./app.py

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    STREAMLIT_SERVER_HEADLESS=true \
    STREAMLIT_BROWSER_GATHER_USAGE_STATS=false

USER nonroot
EXPOSE 8501

CMD ["streamlit", "run", "app.py", "--server.address=0.0.0.0", "--server.port=8501"]
