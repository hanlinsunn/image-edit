import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.config import get_settings
from app.db import SessionLocal, init_db
from app.routers import edits, ingest, results, users
from app.services.prompts import seed_prompt_templates

logging.basicConfig(level=logging.INFO)


@asynccontextmanager
async def lifespan(_: FastAPI):
    init_db()
    with SessionLocal() as session:
        seed_prompt_templates(session)
        session.commit()
    yield


app = FastAPI(
    title="Auto Image Edit API",
    version="0.1.0",
    summary="HTTP/JSON API behind the daily AI photo resurfacing app",
    lifespan=lifespan,
)

app.include_router(users.router)
app.include_router(ingest.router)
app.include_router(edits.router)
app.include_router(results.router)


@app.get("/health", tags=["ops"])
def health() -> dict:
    return {"status": "ok", "environment": get_settings().environment}
