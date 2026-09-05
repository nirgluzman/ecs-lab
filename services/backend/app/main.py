"""FastAPI app exposing CRUD over a single `items` collection.

Interactive docs: http://localhost:8000/docs
"""

from typing import Annotated

from fastapi import FastAPI, HTTPException, Query, Request, status
from pymongo import ReturnDocument

from .db import ItemsDep, lifespan, object_id
from .models import Item, ItemIn, to_item

app = FastAPI(title="Items API", version="0.1.0", lifespan=lifespan)


@app.get("/health", tags=["ops"])
async def health(request: Request) -> dict[str, str]:
    """Liveness + database reachability, used by the compose healthcheck."""
    try:
        await request.app.state.mongo.admin.command("ping")
    except Exception as exc:  # noqa: BLE001 - surface any driver error as 503
        raise HTTPException(status_code=503, detail=f"mongodb unreachable: {exc}") from exc
    return {"status": "ok"}


@app.post("/items", response_model=Item, status_code=status.HTTP_201_CREATED, tags=["items"])
async def create_item(payload: ItemIn, items: ItemsDep) -> Item:
    """Insert one item; MongoDB generates the id."""
    result = await items.insert_one(payload.model_dump())
    return Item(id=str(result.inserted_id), **payload.model_dump())


@app.get("/items", response_model=list[Item], tags=["items"])
async def list_items(
    items: ItemsDep, limit: Annotated[int, Query(ge=1, le=1000)] = 100
) -> list[Item]:
    """Newest first; `limit` keeps the demo payload small.

    Bounded on purpose: pymongo reads `limit=0` as "no limit", so an unvalidated
    value would return the whole collection instead of capping it.
    """
    cursor = items.find().sort("_id", -1).limit(limit)
    return [to_item(doc) async for doc in cursor]


@app.get("/items/{item_id}", response_model=Item, tags=["items"])
async def get_item(item_id: str, items: ItemsDep) -> Item:
    doc = await items.find_one({"_id": object_id(item_id)})
    if doc is None:
        raise HTTPException(status_code=404, detail="Item not found")
    return to_item(doc)


@app.put("/items/{item_id}", response_model=Item, tags=["items"])
async def update_item(item_id: str, payload: ItemIn, items: ItemsDep) -> Item:
    """Full replace of the mutable fields; returns the stored document."""
    doc = await items.find_one_and_update(
        {"_id": object_id(item_id)},
        {"$set": payload.model_dump()},
        return_document=ReturnDocument.AFTER,
    )
    if doc is None:
        raise HTTPException(status_code=404, detail="Item not found")
    return to_item(doc)


@app.delete("/items/{item_id}", status_code=status.HTTP_204_NO_CONTENT, tags=["items"])
async def delete_item(item_id: str, items: ItemsDep) -> None:
    result = await items.delete_one({"_id": object_id(item_id)})
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Item not found")
