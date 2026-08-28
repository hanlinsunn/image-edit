from fastapi import Depends

from app.config import Settings, get_settings
from app.editor.base import ImageEditor
from app.editor.factory import build_image_editor
from app.services.storage import ObjectStorage, build_storage


def get_storage(settings: Settings = Depends(get_settings)) -> ObjectStorage:
    return build_storage(settings)


def get_image_editor(settings: Settings = Depends(get_settings)) -> ImageEditor:
    return build_image_editor(settings)
