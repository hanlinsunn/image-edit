"""Edit pipeline: ingested photo -> matched prompt -> edited result.

The uploaded original is deleted as soon as its edit succeeds; only the edited
result is retained, and only for the configured retention window.
"""

from __future__ import annotations

import logging
import uuid
from datetime import timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import Settings
from app.editor.base import EditRequest, ImageEditor, ImageEditorError
from app.models import EditResult, IngestedPhoto, PromptTemplate, User, utcnow
from app.schemas import PhotoTags
from app.services.matching import match_template
from app.services.storage import ObjectStorage

logger = logging.getLogger(__name__)

RECENT_TEMPLATE_WINDOW_DAYS = 7


def recently_used_templates(session: Session, user: User) -> set[str]:
    since = utcnow() - timedelta(days=RECENT_TEMPLATE_WINDOW_DAYS)
    slugs = session.scalars(
        select(EditResult.template_slug).where(
            EditResult.user_id == user.id, EditResult.created_at >= since
        )
    )
    return set(slugs)


def edit_photo(
    session: Session,
    settings: Settings,
    storage: ObjectStorage,
    editor: ImageEditor,
    user: User,
    photo: IngestedPhoto,
    template: PromptTemplate | None = None,
) -> EditResult:
    """Edit one ingested photo, storing the result and deleting the original."""
    if photo.original_key is None:
        raise ValueError(f"photo {photo.id} has no stored original")

    if template is None:
        tags = PhotoTags.model_validate(photo.tags)
        template = match_template(session, tags, recently_used_templates(session, user)).template

    original = storage.get(settings.upload_bucket, photo.original_key)
    created_at = utcnow()
    result = EditResult(
        user_id=user.id,
        photo_id=photo.id,
        client_asset_id=photo.client_asset_id,
        template_id=template.id,
        template_slug=template.slug,
        storage_key="",
        created_at=created_at,
        expires_at=EditResult.expiry_from(created_at, settings.result_retention_days),
    )

    try:
        edited = editor.edit(
            EditRequest(
                image=original,
                content_type=photo.content_type,
                prompt=template.prompt_text,
                params=template.model_params or {},
            )
        )
    except ImageEditorError as exc:
        result.status = "failed"
        result.error_message = str(exc)
        session.add(result)
        session.flush()
        logger.warning(
            "edit_failed",
            extra={"photo_id": photo.id, "template": template.slug, "retryable": exc.retryable},
        )
        raise

    key = f"{user.id}/{uuid.uuid4()}.png"
    storage.put(settings.result_bucket, key, edited.data, edited.content_type)
    result.storage_key = key
    result.content_type = edited.content_type
    result.status = "ready"
    session.add(result)
    session.flush()

    # Retention guarantee: the original never outlives a successful edit.
    storage.delete(settings.upload_bucket, photo.original_key)
    photo.original_key = None
    session.flush()

    logger.info("edit_succeeded", extra={"photo_id": photo.id, "template": template.slug})
    return result
