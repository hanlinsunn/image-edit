"""OpenAI ``gpt-image-1`` implementation of :class:`ImageEditor`."""

from __future__ import annotations

import base64
import time

import httpx

from app.editor.base import (
    EditedImage,
    EditRequest,
    ImageEditor,
    PermanentEditorError,
    TransientEditorError,
)

_API_URL = "https://api.openai.com/v1/images/edits"
_RETRYABLE_STATUS = {408, 409, 429, 500, 502, 503, 504}
_EXTENSION_BY_CONTENT_TYPE = {
    "image/jpeg": "jpg",
    "image/jpg": "jpg",
    "image/png": "png",
    "image/webp": "webp",
}


class OpenAIImageEditor(ImageEditor):
    def __init__(
        self,
        api_key: str,
        model: str = "gpt-image-1",
        timeout_seconds: float = 120.0,
        max_retries: int = 3,
        client: httpx.Client | None = None,
    ) -> None:
        if not api_key:
            raise PermanentEditorError("OpenAI API key is not configured")
        self._api_key = api_key
        self._model = model
        self._max_retries = max_retries
        self._client = client or httpx.Client(timeout=timeout_seconds)

    def edit(self, request: EditRequest) -> EditedImage:
        extension = _EXTENSION_BY_CONTENT_TYPE.get(request.content_type)
        if extension is None:
            raise PermanentEditorError(f"unsupported content type: {request.content_type}")

        files = {"image": (f"source.{extension}", request.image, request.content_type)}
        data = {"model": self._model, "prompt": request.prompt}
        for key, value in request.params.items():
            data[key] = str(value)

        last_error: Exception | None = None
        for attempt in range(self._max_retries):
            try:
                response = self._client.post(
                    _API_URL,
                    headers={"Authorization": f"Bearer {self._api_key}"},
                    data=data,
                    files=files,
                )
            except httpx.TimeoutException as exc:
                last_error = exc
            except httpx.HTTPError as exc:
                raise PermanentEditorError(f"OpenAI request failed: {exc}") from exc
            else:
                if response.status_code == 200:
                    return self._parse(response.json())
                if response.status_code in _RETRYABLE_STATUS:
                    last_error = TransientEditorError(
                        f"OpenAI returned {response.status_code}: {response.text[:500]}"
                    )
                else:
                    raise PermanentEditorError(
                        f"OpenAI returned {response.status_code}: {response.text[:500]}"
                    )

            if attempt < self._max_retries - 1:
                time.sleep(2**attempt)

        raise TransientEditorError(
            f"OpenAI edit failed after {self._max_retries} attempts: {last_error}"
        )

    def _parse(self, payload: dict) -> EditedImage:
        try:
            encoded = payload["data"][0]["b64_json"]
        except (KeyError, IndexError) as exc:
            raise PermanentEditorError("OpenAI response did not contain image data") from exc
        return EditedImage(
            data=base64.b64decode(encoded), content_type="image/png", model=self._model
        )
