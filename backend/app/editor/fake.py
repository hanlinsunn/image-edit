"""Deterministic editor used by tests and local development.

Output is a real PNG so the whole pipeline can be exercised and the results
viewed without an OpenAI key. The colour is derived from the source bytes and
the prompt, so each photo/template pair yields a distinct, reproducible image.
"""

from __future__ import annotations

import hashlib
import struct
import zlib

from app.editor.base import EditedImage, EditRequest, ImageEditor, TransientEditorError

_SIGNATURE = b"\x89PNG\r\n\x1a\n"
_SIZE = 64


def _chunk(kind: bytes, payload: bytes) -> bytes:
    body = kind + payload
    return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body))


def _solid_png(rgb: tuple[int, int, int]) -> bytes:
    row = b"\x00" + bytes(rgb) * _SIZE
    header = struct.pack(">IIBBBBB", _SIZE, _SIZE, 8, 2, 0, 0, 0)
    return (
        _SIGNATURE
        + _chunk(b"IHDR", header)
        + _chunk(b"IDAT", zlib.compress(row * _SIZE))
        + _chunk(b"IEND", b"")
    )


class FakeImageEditor(ImageEditor):
    def __init__(self, fail_times: int = 0) -> None:
        self._fail_times = fail_times
        self.calls: list[EditRequest] = []

    def edit(self, request: EditRequest) -> EditedImage:
        self.calls.append(request)
        if self._fail_times > 0:
            self._fail_times -= 1
            raise TransientEditorError("simulated transient failure")
        digest = hashlib.sha256(request.image + request.prompt.encode()).digest()
        return EditedImage(
            data=_solid_png((digest[0], digest[1], digest[2])),
            content_type="image/png",
            model="fake",
        )
