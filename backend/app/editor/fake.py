"""Deterministic editor used by tests and local development."""

from __future__ import annotations

import hashlib

from app.editor.base import EditedImage, EditRequest, ImageEditor, TransientEditorError


class FakeImageEditor(ImageEditor):
    def __init__(self, fail_times: int = 0) -> None:
        self._fail_times = fail_times
        self.calls: list[EditRequest] = []

    def edit(self, request: EditRequest) -> EditedImage:
        self.calls.append(request)
        if self._fail_times > 0:
            self._fail_times -= 1
            raise TransientEditorError("simulated transient failure")
        digest = hashlib.sha256(request.image + request.prompt.encode()).hexdigest()
        return EditedImage(
            data=b"edited:" + digest.encode(), content_type="image/png", model="fake"
        )
