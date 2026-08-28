"""Object storage adapter.

Uploaded originals and edited results are the only image bytes the backend ever
holds. Both live behind this interface so the local filesystem backend used in
development can be swapped for S3/Supabase Storage without touching callers.
"""

from __future__ import annotations

import shutil
from abc import ABC, abstractmethod
from pathlib import Path

from app.config import Settings


class ObjectStorage(ABC):
    @abstractmethod
    def put(self, bucket: str, key: str, data: bytes, content_type: str) -> str:
        """Store bytes and return the storage key."""

    @abstractmethod
    def get(self, bucket: str, key: str) -> bytes: ...

    @abstractmethod
    def delete(self, bucket: str, key: str) -> None: ...

    @abstractmethod
    def exists(self, bucket: str, key: str) -> bool: ...


class LocalObjectStorage(ObjectStorage):
    """Filesystem-backed storage for local development and tests."""

    def __init__(self, root: str) -> None:
        self.root = Path(root)

    def _path(self, bucket: str, key: str) -> Path:
        return self.root / bucket / key

    def put(self, bucket: str, key: str, data: bytes, content_type: str) -> str:
        path = self._path(bucket, key)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return key

    def get(self, bucket: str, key: str) -> bytes:
        return self._path(bucket, key).read_bytes()

    def delete(self, bucket: str, key: str) -> None:
        path = self._path(bucket, key)
        if path.is_dir():
            shutil.rmtree(path, ignore_errors=True)
        else:
            path.unlink(missing_ok=True)

    def exists(self, bucket: str, key: str) -> bool:
        return self._path(bucket, key).exists()


def build_storage(settings: Settings) -> ObjectStorage:
    if settings.storage_backend == "local":
        return LocalObjectStorage(settings.storage_root)
    raise ValueError(f"unsupported storage backend: {settings.storage_backend}")
