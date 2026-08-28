from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth import get_current_user
from app.config import Settings, get_settings
from app.db import get_session
from app.deps import get_image_editor, get_storage
from app.editor.base import ImageEditor, ImageEditorError
from app.models import IngestedPhoto, IngestJob, PromptTemplate, User
from app.schemas import AdHocEditRequest, EditResultResponse, PromptTemplateResponse
from app.services.pipeline import edit_photo
from app.services.storage import ObjectStorage

router = APIRouter(prefix="/v1", tags=["edits"])


@router.get("/templates", response_model=list[PromptTemplateResponse])
def list_templates(
    _: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> list[PromptTemplateResponse]:
    """The curated template list backing the ad-hoc editing picker."""
    templates = session.scalars(
        select(PromptTemplate).where(PromptTemplate.is_active.is_(True)).order_by(
            PromptTemplate.display_name
        )
    )
    return [
        PromptTemplateResponse(
            id=t.id,
            slug=t.slug,
            display_name=t.display_name,
            category_tags=t.category_tags or [],
            example_image_url=t.example_image_url,
        )
        for t in templates
    ]


@router.post("/jobs/{job_id}/edits", response_model=list[EditResultResponse])
def run_job_edits(
    job_id: str,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
    settings: Settings = Depends(get_settings),
    storage: ObjectStorage = Depends(get_storage),
    editor: ImageEditor = Depends(get_image_editor),
) -> list[EditResultResponse]:
    """Edit every photo of an ingest job with automatically matched prompts.

    M3 runs this from the overnight batch job; until then the client triggers it
    directly. Photos whose original has already been consumed are skipped, so the
    call is idempotent.
    """
    job = session.get(IngestJob, job_id)
    if job is None or job.user_id != user.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "ingest job not found")

    responses: list[EditResultResponse] = []
    for photo in job.photos:
        if photo.original_key is None:
            continue
        try:
            result = edit_photo(session, settings, storage, editor, user, photo)
        except ImageEditorError:
            continue
        template = session.get(PromptTemplate, result.template_id)
        display_name = template.display_name if template else None
        responses.append(EditResultResponse.from_result(result, display_name))

    job.status = "edited" if responses else "failed"
    return responses


@router.post("/edits/adhoc", response_model=EditResultResponse)
def adhoc_edit(
    payload: AdHocEditRequest,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
    settings: Settings = Depends(get_settings),
    storage: ObjectStorage = Depends(get_storage),
    editor: ImageEditor = Depends(get_image_editor),
) -> EditResultResponse:
    """Apply a user-chosen curated template to one already-ingested photo."""
    photo = session.get(IngestedPhoto, payload.photo_id)
    if photo is None or photo.job.user_id != user.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "photo not found")
    if photo.original_key is None:
        raise HTTPException(status.HTTP_409_CONFLICT, "photo original has already been consumed")

    template = session.scalar(
        select(PromptTemplate).where(
            PromptTemplate.slug == payload.template_slug, PromptTemplate.is_active.is_(True)
        )
    )
    if template is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "template not found")

    try:
        result = edit_photo(session, settings, storage, editor, user, photo, template=template)
    except ImageEditorError as exc:
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, f"edit failed: {exc}") from exc
    return EditResultResponse.from_result(result, template.display_name)
