from __future__ import annotations

import base64
from collections.abc import Iterator

import jwt
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

from app.config import Settings, get_settings
from app.db import get_session
from app.deps import get_image_editor, get_storage
from app.editor.fake import FakeImageEditor
from app.main import app
from app.models import Base
from app.services.prompts import seed_prompt_templates
from app.services.storage import LocalObjectStorage

TEST_APPLE_SUBJECT = "000123.apple.subject"


@pytest.fixture
def settings(tmp_path) -> Settings:
    return Settings(
        environment="test",
        database_url="sqlite+pysqlite:///:memory:",
        storage_root=str(tmp_path / "storage"),
        image_editor="fake",
        auth_allow_insecure_tokens=True,
    )


@pytest.fixture
def session_factory(settings: Settings):
    engine = create_engine(
        settings.database_url,
        connect_args={"check_same_thread": False},
        poolclass=__import__("sqlalchemy").pool.StaticPool,
        future=True,
    )
    Base.metadata.create_all(engine)
    return sessionmaker(bind=engine, autoflush=False, expire_on_commit=False, future=True)


@pytest.fixture
def db(session_factory) -> Iterator[Session]:
    with session_factory() as session:
        seed_prompt_templates(session)
        session.commit()
        yield session


@pytest.fixture
def editor() -> FakeImageEditor:
    return FakeImageEditor()


@pytest.fixture
def storage(settings: Settings) -> LocalObjectStorage:
    return LocalObjectStorage(settings.storage_root)


@pytest.fixture
def client(settings, session_factory, editor, storage, db) -> Iterator[TestClient]:
    def override_session() -> Iterator[Session]:
        session = session_factory()
        try:
            yield session
            session.commit()
        finally:
            session.close()

    app.dependency_overrides[get_settings] = lambda: settings
    app.dependency_overrides[get_session] = override_session
    app.dependency_overrides[get_image_editor] = lambda: editor
    app.dependency_overrides[get_storage] = lambda: storage
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


@pytest.fixture
def auth_headers() -> dict[str, str]:
    token = jwt.encode({"sub": TEST_APPLE_SUBJECT, "email": "user@example.com"}, "secret")
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def other_auth_headers() -> dict[str, str]:
    token = jwt.encode({"sub": "000999.other.subject", "email": "other@example.com"}, "secret")
    return {"Authorization": f"Bearer {token}"}


def photo_payload(client_asset_id: str = "asset-1", category: str = "landscape") -> dict:
    return {
        "client_asset_id": client_asset_id,
        "content_type": "image/jpeg",
        "image_base64": base64.b64encode(b"original-bytes-" + client_asset_id.encode()).decode(),
        "tags": {
            "primary_category": category,
            "secondary_categories": [],
            "people_count": 0,
            "named_face_count": 0,
            "time_of_day": "golden_hour",
            "season": "summer",
            "location_type": "nature",
            "is_favorite": True,
            "aesthetic_score": 0.8,
            "vocabulary_version": 1,
        },
    }
