"""The swappable AI image editing interface."""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field


@dataclass(frozen=True)
class EditRequest:
    image: bytes
    content_type: str
    prompt: str
    params: dict = field(default_factory=dict)


@dataclass(frozen=True)
class EditedImage:
    data: bytes
    content_type: str
    model: str


class ImageEditorError(Exception):
    """Base error. ``retryable`` tells the batch job whether to try again."""

    retryable = False


class TransientEditorError(ImageEditorError):
    retryable = True


class PermanentEditorError(ImageEditorError):
    retryable = False


class ImageEditor(ABC):
    @abstractmethod
    def edit(self, request: EditRequest) -> EditedImage:
        """Apply ``request.prompt`` to ``request.image``.

        Raises TransientEditorError for timeouts/rate limits and
        PermanentEditorError for rejected or malformed input.
        """
