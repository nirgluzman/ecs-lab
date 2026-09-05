"""MongoDB wiring: one client per process, opened and closed with the app."""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Annotated

from bson import ObjectId
from bson.errors import InvalidId
from fastapi import Depends, FastAPI, HTTPException, Request
from pymongo import AsyncMongoClient
from pymongo.asynchronous.collection import AsyncCollection

from .config import get_settings

COLLECTION = "items"


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    """Open the connection pool on startup, drain it on shutdown."""
    settings = get_settings()
    client: AsyncMongoClient = AsyncMongoClient(settings.uri)
    app.state.mongo = client
    # get_default_database honours a database named in the URI path (e.g. an SSM
    # value of mongodb://.../prod) and falls back to MONGO_DB when there is none.
    app.state.db = client.get_default_database(default=settings.mongo_db)
    try:
        yield
    finally:
        await client.close()


def get_items(request: Request) -> AsyncCollection:
    """FastAPI dependency handing routes the `items` collection."""
    return request.app.state.db[COLLECTION]


# Alias so routes read as `items: ItemsDep`.
ItemsDep = Annotated[AsyncCollection, Depends(get_items)]


def object_id(item_id: str) -> ObjectId:
    """Parse a path parameter into an ObjectId, 404 if it cannot be one."""
    try:
        return ObjectId(item_id)
    except (InvalidId, TypeError):
        raise HTTPException(status_code=404, detail="Item not found") from None
