from __future__ import annotations

import base64
import binascii
import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.auth import get_current_user
from app.config import Settings, get_settings
from app.db import get_session
from app.deps import get_storage
from app.models import IngestedPhoto, IngestJob, User
from app.schemas import IngestBatchRequest, IngestBatchResponse, IngestPhotoAccepted
from app.services.storage import ObjectStorage

router = APIRouter(prefix="/v1/ingest", tags=["ingest"])

ALLOWED_CONTENT_TYPES = {"image/jpeg", "image/jpg", "image/png", "image/heic", "image/webp"}


@router.post("", response_model=IngestBatchResponse, status_code=status.HTTP_201_CREATED)
def ingest_batch(
    payload: IngestBatchRequest,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
    settings: Settings = Depends(get_settings),
    storage: ObjectStorage = Depends(get_storage),
) -> IngestBatchResponse:
    """Accept the photos the device selected, plus their on-device tags.

    Only these photos ever leave the device. Originals land in the temp upload
    bucket and are deleted as soon as their edit succeeds.
    """
    if not payload.photos:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "batch contains no photos")
    if len(payload.photos) > settings.max_photos_per_batch:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            f"batch exceeds the limit of {settings.max_photos_per_batch} photos",
        )

    job = IngestJob(user_id=user.id, status="received")
    session.add(job)
    session.flush()

    accepted: list[IngestPhotoAccepted] = []
    for item in payload.photos:
        if item.content_type not in ALLOWED_CONTENT_TYPES:
            raise HTTPException(
                status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
                f"unsupported content type: {item.content_type}",
            )
        try:
            data = base64.b64decode(item.image_base64, validate=True)
        except (binascii.Error, ValueError) as exc:
            raise HTTPException(
                status.HTTP_422_UNPROCESSABLE_ENTITY,
                f"photo {item.client_asset_id} is not valid base64",
            ) from exc
        if not data:
            raise HTTPException(
                status.HTTP_422_UNPROCESSABLE_ENTITY, f"photo {item.client_asset_id} is empty"
            )
        if len(data) > settings.max_photo_bytes:
            raise HTTPException(
                status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                f"photo {item.client_asset_id} exceeds {settings.max_photo_bytes} bytes",
            )

        key = f"{user.id}/{job.id}/{uuid.uuid4()}"
        storage.put(settings.upload_bucket, key, data, item.content_type)
        photo = IngestedPhoto(
            job_id=job.id,
            client_asset_id=item.client_asset_id,
            original_key=key,
            content_type=item.content_type,
            byte_size=len(data),
            tags=item.tags.model_dump(mode="json"),
        )
        session.add(photo)
        session.flush()
        accepted.append(
            IngestPhotoAccepted(photo_id=photo.id, client_asset_id=photo.client_asset_id)
        )

    return IngestBatchResponse(job_id=job.id, accepted=accepted)
