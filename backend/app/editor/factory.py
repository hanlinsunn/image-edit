from __future__ import annotations

from app.config import Settings
from app.editor.base import ImageEditor
from app.editor.fake import FakeImageEditor
from app.editor.openai_editor import OpenAIImageEditor


def build_image_editor(settings: Settings) -> ImageEditor:
    if settings.image_editor == "fake":
        return FakeImageEditor()
    if settings.image_editor == "openai":
        return OpenAIImageEditor(
            api_key=settings.openai_api_key or "",
            model=settings.openai_image_model,
            timeout_seconds=settings.openai_timeout_seconds,
            max_retries=settings.openai_max_retries,
        )
    raise ValueError(f"unsupported image editor: {settings.image_editor}")
