import httpx
import pytest

from app.config import Settings
from app.editor.base import (
    EditRequest,
    PermanentEditorError,
    TransientEditorError,
)
from app.editor.factory import build_image_editor
from app.editor.openai_editor import OpenAIImageEditor

REQUEST = EditRequest(image=b"bytes", content_type="image/jpeg", prompt="make it fun")


def transport(handler) -> httpx.Client:
    return httpx.Client(transport=httpx.MockTransport(handler))


def test_openai_editor_returns_decoded_image():
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.headers["Authorization"] == "Bearer key"
        return httpx.Response(200, json={"data": [{"b64_json": "aGVsbG8="}]})

    editor = OpenAIImageEditor(api_key="key", client=transport(handler))
    edited = editor.edit(REQUEST)
    assert edited.data == b"hello"
    assert edited.model == "gpt-image-1"


def test_openai_editor_retries_then_succeeds(monkeypatch):
    monkeypatch.setattr("app.editor.openai_editor.time.sleep", lambda _: None)
    calls = {"n": 0}

    def handler(_: httpx.Request) -> httpx.Response:
        calls["n"] += 1
        if calls["n"] == 1:
            return httpx.Response(429, text="slow down")
        return httpx.Response(200, json={"data": [{"b64_json": "aGVsbG8="}]})

    editor = OpenAIImageEditor(api_key="key", client=transport(handler))
    assert editor.edit(REQUEST).data == b"hello"
    assert calls["n"] == 2


def test_openai_editor_raises_transient_after_retries(monkeypatch):
    monkeypatch.setattr("app.editor.openai_editor.time.sleep", lambda _: None)
    editor = OpenAIImageEditor(
        api_key="key", max_retries=2, client=transport(lambda _: httpx.Response(503))
    )
    with pytest.raises(TransientEditorError):
        editor.edit(REQUEST)


def test_openai_editor_raises_permanent_on_bad_request():
    editor = OpenAIImageEditor(
        api_key="key", client=transport(lambda _: httpx.Response(400, text="nope"))
    )
    with pytest.raises(PermanentEditorError):
        editor.edit(REQUEST)


def test_openai_editor_rejects_unsupported_content_type():
    editor = OpenAIImageEditor(api_key="key", client=transport(lambda _: httpx.Response(200)))
    with pytest.raises(PermanentEditorError):
        editor.edit(EditRequest(image=b"x", content_type="image/gif", prompt="p"))


def test_factory_selects_implementation():
    assert type(build_image_editor(Settings(image_editor="fake"))).__name__ == "FakeImageEditor"
    editor = build_image_editor(Settings(image_editor="openai", openai_api_key="key"))
    assert isinstance(editor, OpenAIImageEditor)
