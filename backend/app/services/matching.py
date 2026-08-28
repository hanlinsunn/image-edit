"""Match a photo's on-device tags to a category-appropriate curated prompt."""

from __future__ import annotations

import logging
from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import PromptTemplate
from app.schemas import PhotoTags
from app.services.prompts import FALLBACK_TEMPLATE_SLUG

logger = logging.getLogger(__name__)

PRIMARY_TAG_WEIGHT = 3.0
SECONDARY_TAG_WEIGHT = 1.0
RECENTLY_USED_PENALTY = 2.5


@dataclass(frozen=True)
class Match:
    template: PromptTemplate
    score: float
    is_fallback: bool


def score_template(template: PromptTemplate, tags: PhotoTags, recently_used: set[str]) -> float:
    template_tags = set(template.category_tags or [])
    score = 0.0
    if tags.primary_category.value in template_tags:
        score += PRIMARY_TAG_WEIGHT
    score += SECONDARY_TAG_WEIGHT * len(
        {tag.value for tag in tags.secondary_categories} & template_tags
    )
    if template.slug in recently_used:
        score -= RECENTLY_USED_PENALTY
    return score


def match_template(
    session: Session, tags: PhotoTags, recently_used: set[str] | None = None
) -> Match:
    """Pick the best active template for ``tags``.

    ``recently_used`` holds template slugs already applied for this user recently;
    they are penalised so a user does not see the same style day after day. Ties
    break on slug so matching is deterministic.
    """
    recently_used = recently_used or set()
    templates = list(
        session.scalars(select(PromptTemplate).where(PromptTemplate.is_active.is_(True)))
    )
    if not templates:
        raise LookupError("prompt library is empty; run the seed script")

    scored = sorted(
        ((score_template(t, tags, recently_used), t.slug, t) for t in templates),
        key=lambda item: (-item[0], item[1]),
    )
    best_score, _, best = scored[0]

    if best_score <= 0:
        fallback = next((t for t in templates if t.slug == FALLBACK_TEMPLATE_SLUG), best)
        logger.info(
            "prompt_match_fallback",
            extra={"primary_category": tags.primary_category.value, "template": fallback.slug},
        )
        return Match(template=fallback, score=best_score, is_fallback=True)

    logger.info(
        "prompt_match",
        extra={
            "primary_category": tags.primary_category.value,
            "template": best.slug,
            "score": best_score,
        },
    )
    return Match(template=best, score=best_score, is_fallback=False)
