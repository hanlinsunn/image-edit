from __future__ import annotations

from datetime import datetime, timezone

from pydantic import BaseModel, Field, field_serializer

from app.models import EditResult
from app.tags import LocationType, PhotoCategory, Season, TimeOfDay


class PhotoTags(BaseModel):
    """Lightweight, on-device derived metadata. No precise coordinates."""

    primary_category: PhotoCategory
    secondary_categories: list[PhotoCategory] = Field(default_factory=list)
    people_count: int = 0
    named_face_count: int = 0
    time_of_day: TimeOfDay | None = None
    season: Season | None = None
    location_type: LocationType = LocationType.UNKNOWN
    is_favorite: bool = False
    aesthetic_score: float = 0.0
    vocabulary_version: int = 1


class IngestPhotoRequest(BaseModel):
    client_asset_id: str
    content_type: str = "image/jpeg"
    image_base64: str
    tags: PhotoTags


class IngestBatchRequest(BaseModel):
    photos: list[IngestPhotoRequest]


class IngestPhotoAccepted(BaseModel):
    photo_id: str
    client_asset_id: str


class IngestBatchResponse(BaseModel):
    job_id: str
    accepted: list[IngestPhotoAccepted]


class EditResultResponse(BaseModel):
    id: str
    client_asset_id: str
    template_slug: str
    template_display_name: str | None = None
    status: str
    download_url: str | None = None
    created_at: datetime
    expires_at: datetime

    @field_serializer("created_at", "expires_at")
    def _as_utc(self, value: datetime) -> datetime:
        """Timestamps are stored naive-UTC; clients get an explicit UTC offset."""
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)

    @classmethod
    def from_result(cls, result: EditResult, display_name: str | None) -> EditResultResponse:
        """Edited bytes are served through the authorizing results route, never a raw key."""
        ready = result.status == "ready"
        return cls(
            id=result.id,
            client_asset_id=result.client_asset_id,
            template_slug=result.template_slug,
            template_display_name=display_name,
            status=result.status,
            download_url=f"/v1/results/{result.id}/content" if ready else None,
            created_at=result.created_at,
            expires_at=result.expires_at,
        )


class PromptTemplateResponse(BaseModel):
    id: str
    slug: str
    display_name: str
    category_tags: list[str]
    example_image_url: str | None = None


class AdHocEditRequest(BaseModel):
    """Ad-hoc edit of a single already-ingested photo with a user-chosen template."""

    photo_id: str
    template_slug: str


class UserResponse(BaseModel):
    id: str
    email: str | None
    timezone: str
