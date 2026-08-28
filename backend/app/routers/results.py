from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth import get_current_user
from app.config import Settings, get_settings
from app.db import get_session
from app.deps import get_storage
from app.models import EditResult, PromptTemplate, User, utcnow
from app.schemas import EditResultResponse
from app.services.storage import ObjectStorage

router = APIRouter(prefix="/v1/results", tags=["results"])


@router.get("", response_model=list[EditResultResponse])
def list_results(
    limit: int = 50,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> list[EditResultResponse]:
    """The caller's unexpired edited photos, newest first."""
    rows = session.execute(
        select(EditResult, PromptTemplate.display_name)
        .join(PromptTemplate, PromptTemplate.id == EditResult.template_id, isouter=True)
        .where(EditResult.user_id == user.id, EditResult.expires_at > utcnow())
        .order_by(EditResult.created_at.desc())
        .limit(min(limit, 200))
    ).all()
    return [EditResultResponse.from_result(result, name) for result, name in rows]


@router.get("/{result_id}/content")
def download_result(
    result_id: str,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
    settings: Settings = Depends(get_settings),
    storage: ObjectStorage = Depends(get_storage),
) -> Response:
    result = session.get(EditResult, result_id)
    if result is None or result.user_id != user.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "result not found")
    if result.status != "ready" or result.expires_at <= utcnow():
        raise HTTPException(status.HTTP_410_GONE, "result is no longer available")
    data = storage.get(settings.result_bucket, result.storage_key)
    return Response(content=data, media_type=result.content_type)
