import base64

from sqlalchemy import select

from app.models import EditResult, IngestedPhoto
from tests.conftest import photo_payload


def ingest(client, headers, photos):
    return client.post("/v1/ingest", json={"photos": photos}, headers=headers)


def test_health(client):
    assert client.get("/health").json()["status"] == "ok"


def test_session_creates_user(client, auth_headers):
    response = client.post("/v1/auth/session", headers=auth_headers)
    assert response.status_code == 200
    assert response.json()["email"] == "user@example.com"


def test_ingest_requires_auth(client):
    assert ingest(client, {}, [photo_payload()]).status_code in (401, 403)


def test_ingest_accepts_batch(client, auth_headers, db):
    response = ingest(client, auth_headers, [photo_payload("a"), photo_payload("b", "food")])
    assert response.status_code == 201
    body = response.json()
    assert len(body["accepted"]) == 2
    stored = db.scalars(select(IngestedPhoto)).all()
    assert {p.client_asset_id for p in stored} == {"a", "b"}
    assert all(p.original_key for p in stored)


def test_ingest_rejects_oversized_batch(client, auth_headers, settings):
    photos = [photo_payload(f"a{i}") for i in range(settings.max_photos_per_batch + 1)]
    assert ingest(client, auth_headers, photos).status_code == 422


def test_ingest_rejects_unsupported_content_type(client, auth_headers):
    payload = photo_payload()
    payload["content_type"] = "image/gif"
    assert ingest(client, auth_headers, [payload]).status_code == 415


def test_ingest_rejects_invalid_base64(client, auth_headers):
    payload = photo_payload()
    payload["image_base64"] = "not base64!!"
    assert ingest(client, auth_headers, [payload]).status_code == 422


def test_ingest_rejects_oversized_photo(client, auth_headers, settings):
    payload = photo_payload()
    payload["image_base64"] = base64.b64encode(b"x" * (settings.max_photo_bytes + 1)).decode()
    assert ingest(client, auth_headers, [payload]).status_code == 413


def test_edit_run_produces_results_and_deletes_originals(
    client, auth_headers, db, storage, settings
):
    job_id = ingest(client, auth_headers, [photo_payload("a"), photo_payload("b", "food")]).json()[
        "job_id"
    ]
    response = client.post(f"/v1/jobs/{job_id}/edits", headers=auth_headers)
    assert response.status_code == 200
    results = response.json()
    assert len(results) == 2
    assert {r["status"] for r in results} == {"ready"}

    photos = db.scalars(select(IngestedPhoto)).all()
    assert all(p.original_key is None for p in photos), "originals must be deleted after editing"
    assert not any(
        storage.exists(settings.upload_bucket, key)
        for key in (r.get("original_key") for r in results)
        if key
    )


def test_edit_run_is_idempotent(client, auth_headers):
    job_id = ingest(client, auth_headers, [photo_payload("a")]).json()["job_id"]
    assert len(client.post(f"/v1/jobs/{job_id}/edits", headers=auth_headers).json()) == 1
    assert client.post(f"/v1/jobs/{job_id}/edits", headers=auth_headers).json() == []


def test_results_are_listed_and_downloadable(client, auth_headers):
    job_id = ingest(client, auth_headers, [photo_payload("a")]).json()["job_id"]
    client.post(f"/v1/jobs/{job_id}/edits", headers=auth_headers)

    listed = client.get("/v1/results", headers=auth_headers).json()
    assert len(listed) == 1
    assert listed[0]["template_display_name"]

    assert listed[0]["download_url"] == f"/v1/results/{listed[0]['id']}/content"

    content = client.get(listed[0]["download_url"], headers=auth_headers)
    assert content.status_code == 200
    assert content.content.startswith(b"edited:")


def test_results_are_private_to_their_owner(client, auth_headers, other_auth_headers):
    job_id = ingest(client, auth_headers, [photo_payload("a")]).json()["job_id"]
    client.post(f"/v1/jobs/{job_id}/edits", headers=auth_headers)
    result_id = client.get("/v1/results", headers=auth_headers).json()[0]["id"]

    assert client.get("/v1/results", headers=other_auth_headers).json() == []
    assert (
        client.get(f"/v1/results/{result_id}/content", headers=other_auth_headers).status_code
        == 404
    )


def test_templates_are_listed(client, auth_headers):
    templates = client.get("/v1/templates", headers=auth_headers).json()
    assert len(templates) >= 10
    assert all(t["display_name"] and t["slug"] for t in templates)


def test_adhoc_edit_applies_chosen_template(client, auth_headers):
    photo_id = ingest(client, auth_headers, [photo_payload("a")]).json()["accepted"][0]["photo_id"]
    response = client.post(
        "/v1/edits/adhoc",
        json={"photo_id": photo_id, "template_slug": "watercolour-memory"},
        headers=auth_headers,
    )
    assert response.status_code == 200
    assert response.json()["template_slug"] == "watercolour-memory"


def test_adhoc_edit_rejects_unknown_template(client, auth_headers):
    photo_id = ingest(client, auth_headers, [photo_payload("a")]).json()["accepted"][0]["photo_id"]
    response = client.post(
        "/v1/edits/adhoc",
        json={"photo_id": photo_id, "template_slug": "does-not-exist"},
        headers=auth_headers,
    )
    assert response.status_code == 404


def test_failed_edit_records_failure(client, auth_headers, editor, db):
    editor._fail_times = 1
    job_id = ingest(client, auth_headers, [photo_payload("a")]).json()["job_id"]
    assert client.post(f"/v1/jobs/{job_id}/edits", headers=auth_headers).json() == []
    failed = db.scalars(select(EditResult)).all()
    assert [r.status for r in failed] == ["failed"]
