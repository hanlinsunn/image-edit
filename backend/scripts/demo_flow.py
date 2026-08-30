#!/usr/bin/env python3
"""Drive the whole backend flow end-to-end against a running server.

Sign-in, ingest of the selected photos, prompt matching plus editing, the results
list and the edited downloads — the same sequence the iOS app performs. Edited
images are written to an output directory so the result can be inspected without
the app.

    uvicorn app.main:app --port 8000          # in another shell
    python scripts/demo_flow.py photo1.jpg photo2.jpg

Requires ``APP_AUTH_ALLOW_INSECURE_TOKENS=true`` on the server: the script mints
its own unsigned Apple-shaped identity token instead of signing in with Apple.
"""

from __future__ import annotations

import argparse
import base64
import sys
from pathlib import Path

import httpx
import jwt

CONTENT_TYPES = {
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".heic": "image/heic",
    ".webp": "image/webp",
}
CATEGORIES = [
    "landscape",
    "group_of_friends",
    "food",
    "cityscape",
    "pet",
]


def mint_token(subject: str) -> str:
    """An Apple identity token minus the signature, accepted in insecure dev mode."""
    return jwt.encode({"sub": subject, "email": f"{subject}@example.com"}, "unused")


def build_photo(path: Path, category: str) -> dict[str, object]:
    content_type = CONTENT_TYPES.get(path.suffix.lower())
    if content_type is None:
        raise SystemExit(f"unsupported file type: {path.name}")
    return {
        "client_asset_id": path.stem,
        "content_type": content_type,
        "image_base64": base64.b64encode(path.read_bytes()).decode(),
        "tags": {
            "primary_category": category,
            "secondary_categories": [],
            "people_count": 3 if category == "group_of_friends" else 0,
            "named_face_count": 0,
            "time_of_day": "golden_hour",
            "season": "summer",
            "location_type": "nature",
            "is_favorite": True,
            "aesthetic_score": 0.8,
            "vocabulary_version": 1,
        },
    }


def check(response: httpx.Response, step: str) -> httpx.Response:
    if response.is_error:
        raise SystemExit(f"{step} failed: HTTP {response.status_code} {response.text}")
    return response


def write_result(
    client: httpx.Client, result: dict[str, object], output: Path, prefix: str = ""
) -> None:
    if not result["download_url"]:
        print(f"  {result['client_asset_id']}: {result['status']}")
        return
    content = check(client.get(str(result["download_url"])), "download")
    suffix = ".png" if "png" in content.headers["content-type"] else ".jpg"
    name = f"{prefix}{result['client_asset_id']}-{result['template_slug']}{suffix}"
    destination = output / name
    destination.write_bytes(content.content)
    print(f"  wrote {destination} (expires {result['expires_at']})")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("images", nargs="*", type=Path, help="photos to send (max 5)")
    parser.add_argument("--base-url", default="http://localhost:8000")
    parser.add_argument("--subject", default="000123.demo.subject", help="fake Apple user id")
    parser.add_argument("--output", type=Path, default=Path("demo-output"))
    parser.add_argument(
        "--category",
        action="append",
        default=None,
        help="tag category per photo; cycles through a default mix when omitted",
    )
    args = parser.parse_args()

    token = mint_token(args.subject)
    print(f"bearer token (paste into /docs → Authorize):\n{token}\n")

    if not args.images:
        raise SystemExit("pass at least one image path, e.g. python scripts/demo_flow.py a.jpg")
    if len(args.images) > 5:
        raise SystemExit("the daily batch is 5 photos; pass at most 5")
    for path in args.images:
        if not path.is_file():
            raise SystemExit(f"no such file: {path}")

    categories = args.category or CATEGORIES
    photos = [
        build_photo(path, categories[index % len(categories)])
        for index, path in enumerate(args.images)
    ]

    with httpx.Client(
        base_url=args.base_url,
        headers={"Authorization": f"Bearer {token}"},
        timeout=180.0,
    ) as client:
        me = check(client.post("/v1/auth/session"), "sign-in").json()
        print(f"signed in as user {me['id']} ({me['email']})")

        job = check(client.post("/v1/ingest", json={"photos": photos}), "ingest").json()
        print(f"ingested {len(job['accepted'])} photo(s) as job {job['job_id']}")

        edits = check(client.post(f"/v1/jobs/{job['job_id']}/edits"), "editing").json()
        for edit in edits:
            print(f"  {edit['client_asset_id']} -> {edit['template_display_name']}")

        results = check(client.get("/v1/results"), "results").json()
        args.output.mkdir(parents=True, exist_ok=True)
        for result in results:
            write_result(client, result, args.output)

        templates = check(client.get("/v1/templates"), "templates").json()
        print(f"\n{len(templates)} curated templates for the ad-hoc picker:")
        print("  " + ", ".join(t["slug"] for t in templates))

        # Ad-hoc edits need an unconsumed original, so re-ingest the first photo.
        chosen = templates[0]
        adhoc_job = check(client.post("/v1/ingest", json={"photos": photos[:1]}), "ingest").json()
        adhoc = check(
            client.post(
                "/v1/edits/adhoc",
                json={
                    "photo_id": adhoc_job["accepted"][0]["photo_id"],
                    "template_slug": chosen["slug"],
                },
            ),
            "ad-hoc edit",
        ).json()
        print(f"\nad-hoc edit with '{chosen['display_name']}':")
        write_result(client, adhoc, args.output, prefix="adhoc-")
    return 0


if __name__ == "__main__":
    sys.exit(main())
