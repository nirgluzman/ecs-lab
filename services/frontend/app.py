"""Streamlit UI over the Items API.

Deliberately thin: it owns no state and talks to the backend only over HTTP,
so the two services stay independently deployable.
"""

import os
from typing import Any

import requests
import streamlit as st

# Service-to-service URL. On compose this is the backend service name; on ECS it
# becomes a service-discovery name or load balancer DNS.
BACKEND_URL = os.getenv("BACKEND_URL", "http://localhost:8000").rstrip("/")
TIMEOUT = 5  # seconds, per request


def decode(response: requests.Response) -> Any:
    """Body as JSON when it is JSON, otherwise the raw text.

    Error bodies are not always JSON - a load balancer in front of the backend
    answers 502/504 with HTML - so `.json()` must never be called unguarded.
    """
    try:
        return response.json()
    except ValueError:
        return response.text or response.reason


def api(method: str, path: str, **kwargs) -> requests.Response | None:
    """Single place where HTTP and transport errors are turned into a message.

    Returns the response only when the call succeeded, otherwise None. A
    `Response` is truthy exactly when `.ok`, so callers can just test the result.
    """
    try:
        response = requests.request(
            method, f"{BACKEND_URL}{path}", timeout=TIMEOUT, **kwargs
        )
    except requests.RequestException as exc:
        st.error(f"{method} {path} failed: {exc}")
        return None
    if not response.ok:
        body = decode(response)
        detail = body.get("detail", body) if isinstance(body, dict) else body
        st.error(f"{method} {path} failed ({response.status_code}): {detail}")
        return None
    return response


st.set_page_config(page_title="Items", page_icon="*", layout="centered")
st.title("Items")
st.caption(f"backend: {BACKEND_URL}")

# --- Health banner -----------------------------------------------------------
try:
    healthy = requests.get(f"{BACKEND_URL}/health", timeout=TIMEOUT).ok
except requests.RequestException as exc:
    st.error(f"Backend unreachable: {exc}")
    st.stop()
if not healthy:
    st.warning("Backend is up but MongoDB is not reachable.")

# --- Create ------------------------------------------------------------------
with st.form("create", clear_on_submit=True):
    st.subheader("Add item")
    name = st.text_input("Name", max_chars=100)
    description = st.text_area("Description", max_chars=500)
    quantity = st.number_input("Quantity", min_value=0, step=1, value=0)
    if st.form_submit_button("Create", type="primary"):
        if not name.strip():
            st.warning("Name is required.")
        else:
            payload = {
                "name": name.strip(),
                "description": description.strip() or None,
                "quantity": int(quantity),
            }
            if api("POST", "/items", json=payload):
                st.success(f"Created {name}.")

# --- List / update / delete --------------------------------------------------
st.subheader("Existing items")
response = api("GET", "/items")
if response is None:
    st.stop()
items = decode(response)
if not isinstance(items, list):
    st.error("Unexpected response from GET /items - expected a list of items.")
    st.stop()
if not items:
    st.info("No items yet.")

for item in items:
    # One expander per item; the nested form does the update, the button deletes.
    with st.expander(f"{item['name']}  -  qty {item['quantity']}"):
        with st.form(f"edit-{item['id']}"):
            new_name = st.text_input("Name", value=item["name"], key=f"n-{item['id']}")
            new_description = st.text_area(
                "Description",
                value=item.get("description") or "",
                key=f"d-{item['id']}",
            )
            new_quantity = st.number_input(
                "Quantity",
                min_value=0,
                step=1,
                value=item["quantity"],
                key=f"q-{item['id']}",
            )
            save, delete = st.columns(2)
            if save.form_submit_button("Save"):
                if not new_name.strip():
                    st.warning("Name is required.")
                    st.stop()
                payload = {
                    "name": new_name.strip(),
                    "description": new_description.strip() or None,
                    "quantity": int(new_quantity),
                }
                if api("PUT", f"/items/{item['id']}", json=payload):
                    st.rerun()
            if delete.form_submit_button("Delete"):
                if api("DELETE", f"/items/{item['id']}"):
                    st.rerun()
        st.caption(f"id: {item['id']}")
