from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import (
    JSON,
    Boolean,
    DateTime,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


def _uuid() -> str:
    return str(uuid.uuid4())


def utcnow() -> datetime:
    """Naive UTC. Timestamps are stored without an offset and are always UTC."""
    return datetime.now(timezone.utc).replace(tzinfo=None)


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    apple_subject: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    email: Mapped[str | None] = mapped_column(String(320), nullable=True)
    is_private_relay_email: Mapped[bool] = mapped_column(Boolean, default=False)
    timezone: Mapped[str] = mapped_column(String(64), default="UTC")
    created_at: Mapped[datetime] = mapped_column(DateTime(), default=utcnow)

    ingests: Mapped[list[IngestJob]] = relationship(back_populates="user")
    results: Mapped[list[EditResult]] = relationship(back_populates="user")


class PromptTemplate(Base):
    """A hand-curated editing prompt, tagged with the shared photo category vocabulary."""

    __tablename__ = "prompt_templates"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    slug: Mapped[str] = mapped_column(String(80), unique=True, index=True)
    display_name: Mapped[str] = mapped_column(String(120))
    prompt_text: Mapped[str] = mapped_column(Text)
    category_tags: Mapped[list[str]] = mapped_column(JSON, default=list)
    model_params: Mapped[dict] = mapped_column(JSON, default=dict)
    example_image_url: Mapped[str | None] = mapped_column(String(1024), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    version: Mapped[int] = mapped_column(Integer, default=1)
    source: Mapped[str] = mapped_column(String(32), default="curated")
    created_at: Mapped[datetime] = mapped_column(DateTime(), default=utcnow)


class IngestJob(Base):
    """One upload batch from a client. Originals live only until their edit succeeds."""

    __tablename__ = "ingest_jobs"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    status: Mapped[str] = mapped_column(String(24), default="pending")
    created_at: Mapped[datetime] = mapped_column(DateTime(), default=utcnow)

    user: Mapped[User] = relationship(back_populates="ingests")
    photos: Mapped[list[IngestedPhoto]] = relationship(
        back_populates="job", cascade="all, delete-orphan"
    )


class IngestedPhoto(Base):
    __tablename__ = "ingested_photos"
    __table_args__ = (UniqueConstraint("job_id", "client_asset_id"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    job_id: Mapped[str] = mapped_column(ForeignKey("ingest_jobs.id"), index=True)
    client_asset_id: Mapped[str] = mapped_column(String(128))
    original_key: Mapped[str | None] = mapped_column(String(512), nullable=True)
    content_type: Mapped[str] = mapped_column(String(64))
    byte_size: Mapped[int] = mapped_column(Integer)
    tags: Mapped[dict] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime(), default=utcnow)

    job: Mapped[IngestJob] = relationship(back_populates="photos")


class EditResult(Base):
    __tablename__ = "edit_results"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    photo_id: Mapped[str] = mapped_column(ForeignKey("ingested_photos.id"), index=True)
    client_asset_id: Mapped[str] = mapped_column(String(128))
    template_id: Mapped[str] = mapped_column(ForeignKey("prompt_templates.id"))
    template_slug: Mapped[str] = mapped_column(String(80))
    storage_key: Mapped[str] = mapped_column(String(512))
    content_type: Mapped[str] = mapped_column(String(64), default="image/png")
    status: Mapped[str] = mapped_column(String(24), default="ready")
    error_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(), default=utcnow)
    expires_at: Mapped[datetime] = mapped_column(DateTime(), default=utcnow)

    user: Mapped[User] = relationship(back_populates="results")

    @staticmethod
    def expiry_from(created: datetime, retention_days: int) -> datetime:
        return created + timedelta(days=retention_days)
