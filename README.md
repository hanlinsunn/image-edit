# image-edit

Automatic fun image editing product. Goes through your photos and generates fun photos.

This repository holds milestones **M1 (on-device selection)** and **M2 (editing pipeline)**:
an iOS app that scans the Photos library on-device and a FastAPI backend that edits the
handful of photos the app chooses to upload.

```
backend/                FastAPI service: ingest, prompt matching, AI editing, results
ios/AutoImageEdit/      SwiftUI app: Sign in with Apple, PhotoKit + Vision, feed, results
ios/Packages/PhotoCuration/  Platform-agnostic selection logic (filter/cluster/score/tag) + tests
```

## Backend

```bash
cd backend
python3 -m venv .venv && . .venv/bin/activate
pip install -e ".[dev]"
cp .env.example .env
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Defaults are development-safe: SQLite, local object storage under `.storage/`, and the
fake image editor. Set `APP_IMAGE_EDITOR=openai` plus `APP_OPENAI_API_KEY` to use
`gpt-image-1`. Tables are created and the prompt library is seeded on startup.

Checks:

```bash
ruff check . && mypy app && pytest
```

### Trying the pipeline without the app

`scripts/demo_flow.py` performs the same sequence as the iOS client — sign in, ingest,
prompt matching and editing, results listing, downloads, and one ad-hoc template edit —
and writes the edited images to `demo-output/`:

```bash
APP_AUTH_ALLOW_INSECURE_TOKENS=true uvicorn app.main:app --port 8000   # one shell
python scripts/demo_flow.py ~/Pictures/a.jpg ~/Pictures/b.jpg          # another
```

The insecure-token flag lets the script mint its own Apple-shaped identity token instead
of signing in with Apple; it also prints that token, so you can paste it into
**Authorize** at http://localhost:8000/docs and drive the endpoints by hand. With the
fake editor each edit is a deterministic colour swatch; point it at `openai` to get real
`gpt-image-1` output.

### API

| Method | Path | Purpose |
| --- | --- | --- |
| POST | `/v1/auth/session` | Exchange an Apple identity token for the backend user |
| GET | `/v1/me` | Current user |
| POST | `/v1/ingest` | Upload up to 5 selected photos plus lightweight tags |
| POST | `/v1/jobs/{job_id}/edits` | Match prompts and edit every photo in a job |
| POST | `/v1/edits/adhoc` | Apply a curated template to one uploaded photo |
| GET | `/v1/templates` | Curated template list for the ad-hoc picker |
| GET | `/v1/results` | The caller's unexpired edited results |
| GET | `/v1/results/{id}/content` | Download an edited image |

Every request carries `Authorization: Bearer <apple identity token>`. Originals are
deleted the moment an edit succeeds; results expire after 30 days.

## iOS app

Requires **Xcode 16+** and a **physical device** — PhotoKit, Vision and Sign in with Apple
are not usable in a way that proves anything on the simulator.

1. `open ios/AutoImageEdit.xcodeproj`
2. Select the `AutoImageEdit` target → Signing & Capabilities → set your team. The bundle
   ID defaults to `com.hanlinsunn.imageedit`; change it if the identifier is taken.
   Sign in with Apple and Push Notifications capabilities are already in the entitlements.
3. Point the app at your backend: target build settings → `BACKEND_BASE_URL`
   (e.g. `http://192.168.1.20:8000` — your Mac's LAN address, not `localhost`, when
   running on a device). App Transport Security only whitelists local networking, so
   plain-HTTP access to an arbitrary private IP may be blocked — tunnel the backend over
   HTTPS (e.g. `ngrok http 8000`) if the device refuses to connect.
4. Run on the device, sign in, accept full photo access, then **Scan**.

The curation logic is a Swift package so it can be tested without a device:

```bash
cd ios/Packages/PhotoCuration && swift test
```

## What runs where

- Library scanning, Vision analysis, clustering, scoring and tagging: on-device only.
- Uploaded to the backend: the five chosen photos (JPEG, max 1536px) plus coarse tags.
  Precise GPS never leaves the device — locations are reduced to a coarse type and a
  rounded grid cell used only for grouping photos into trips.
