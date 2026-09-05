"""Request/response shapes. MongoDB's `_id` is exposed to clients as a string `id`."""

from typing import Any

from pydantic import BaseModel, Field


class ItemIn(BaseModel):
    """Payload accepted on create (POST) and full update (PUT)."""

    name: str = Field(min_length=1, max_length=100)
    description: str | None = Field(default=None, max_length=500)
    quantity: int = Field(default=0, ge=0)


class Item(ItemIn):
    """An item as stored, including its generated id."""

    id: str


def to_item(doc: dict[str, Any]) -> Item:
    """Map a raw BSON document onto the API model."""
    return Item(
        id=str(doc["_id"]),
        name=doc["name"],
        description=doc.get("description"),
        quantity=doc.get("quantity", 0),
    )
