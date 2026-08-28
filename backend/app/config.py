from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime configuration. Every secret is injected through the environment."""

    model_config = SettingsConfigDict(env_file=".env", env_prefix="APP_", extra="ignore")

    environment: str = "dev"
    database_url: str = "sqlite+pysqlite:///./dev.db"

    # Storage. ``local`` writes under storage_root; ``s3`` is wired through the same
    # ObjectStorage interface once a bucket is provisioned (see AIE-31).
    storage_backend: str = "local"
    storage_root: str = "./.storage"
    upload_bucket: str = "auto-image-edit-uploads"
    result_bucket: str = "auto-image-edit-results"
    result_retention_days: int = 30

    # Editing
    image_editor: str = "fake"  # "fake" | "openai"
    openai_api_key: str | None = None
    openai_image_model: str = "gpt-image-1"
    openai_timeout_seconds: float = 120.0
    openai_max_retries: int = 3

    # Auth
    apple_bundle_id: str = "com.hanlinsunn.imageedit"
    apple_keys_url: str = "https://appleid.apple.com/auth/keys"
    apple_issuer: str = "https://appleid.apple.com"
    auth_allow_insecure_tokens: bool = False  # dev/test only: skip Apple signature check

    # Ingest limits
    max_photos_per_batch: int = 5
    max_photo_bytes: int = 25 * 1024 * 1024
    daily_batch_size: int = 5


@lru_cache
def get_settings() -> Settings:
    return Settings()
