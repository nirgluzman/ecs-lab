"""Configuration, read once from environment variables.

Locally the values come from services/.env via docker compose. In AWS the same
variable names are fed from SSM Parameter Store, so nothing here changes.
"""

from functools import lru_cache
from urllib.parse import quote_plus

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Every field is overridable by an env var of the same (case-insensitive) name."""

    mongo_host: str = "mongodb"
    mongo_port: int = 27017
    mongo_username: str = "app"
    mongo_password: str = "app"
    mongo_db: str = "appdb"
    mongo_auth_source: str = "appdb"  # DB the app user was created in

    # Escape hatch: a full connection string wins over the parts above. Handy when
    # AWS hands over one ready-made URI (e.g. a single SecureString parameter).
    mongo_uri: str | None = None

    @property
    def uri(self) -> str:
        """Connection string; credentials are percent-encoded to survive odd characters."""
        if self.mongo_uri:
            return self.mongo_uri
        user = quote_plus(self.mongo_username)
        password = quote_plus(self.mongo_password)
        return (
            f"mongodb://{user}:{password}@{self.mongo_host}:{self.mongo_port}"
            f"/?authSource={self.mongo_auth_source}"
        )


@lru_cache
def get_settings() -> Settings:
    """Cached so the environment is parsed once per process."""
    return Settings()
