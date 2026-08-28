"""Curated prompt library seed content.

Prompts are hand-written and tagged with the shared photo category vocabulary so
they can be matched automatically and offered in the ad-hoc template picker.
"""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import PromptTemplate
from app.tags import PhotoCategory as C

SEED_TEMPLATES: list[dict] = [
    {
        "slug": "golden-hour-glow",
        "display_name": "Golden Hour Glow",
        "prompt_text": (
            "Relight this photo with warm golden-hour sunlight and soft rim light on the "
            "subjects. Keep faces, poses and composition exactly as they are; enhance colour "
            "and light only."
        ),
        "category_tags": [C.LANDSCAPE, C.BEACH, C.MOUNTAIN, C.PORTRAIT],
    },
    {
        "slug": "epic-landscape-poster",
        "display_name": "Epic Landscape Poster",
        "prompt_text": (
            "Turn this landscape into a dramatic travel poster: deepen the sky, add gentle "
            "atmospheric haze in the distance and boost contrast in the terrain. Do not add "
            "or remove any landmarks."
        ),
        "category_tags": [C.LANDSCAPE, C.MOUNTAIN],
    },
    {
        "slug": "friends-film-grain",
        "display_name": "Film Camera Night Out",
        "prompt_text": (
            "Restyle this group photo as a 35mm film snapshot: warm grain, slight halation "
            "around lights and punchy colour. Keep every face natural, recognisable and "
            "unretouched in shape."
        ),
        "category_tags": [C.GROUP_OF_FRIENDS, C.NIGHTLIFE, C.CELEBRATION],
    },
    {
        "slug": "friends-confetti-party",
        "display_name": "Confetti Party",
        "prompt_text": (
            "Add a joyful burst of falling confetti and festive bokeh lights behind this "
            "group, matched to the existing lighting. Do not alter the people themselves."
        ),
        "category_tags": [C.GROUP_OF_FRIENDS, C.CELEBRATION],
    },
    {
        "slug": "studio-portrait-light",
        "display_name": "Studio Portrait Light",
        "prompt_text": (
            "Relight this portrait with soft studio key light and a gentle background "
            "falloff. Preserve the person's features, skin texture and expression exactly."
        ),
        "category_tags": [C.PORTRAIT],
    },
    {
        "slug": "cityscape-neon-night",
        "display_name": "Neon City Night",
        "prompt_text": (
            "Restyle this cityscape as a neon-lit night scene with reflective wet streets and "
            "saturated signage glow, keeping the skyline and architecture unchanged."
        ),
        "category_tags": [C.CITYSCAPE, C.ARCHITECTURE, C.NIGHTLIFE],
    },
    {
        "slug": "food-magazine-shot",
        "display_name": "Food Magazine Shot",
        "prompt_text": (
            "Make this dish look like a food magazine cover: crisp directional light, richer "
            "colour, clean soft-focus background. Keep the food itself exactly as served."
        ),
        "category_tags": [C.FOOD],
    },
    {
        "slug": "pet-portrait-hero",
        "display_name": "Pet Hero Portrait",
        "prompt_text": (
            "Turn this pet photo into a charming hero portrait with soft light, a creamy "
            "blurred background and sharp eyes. Keep the animal's markings and shape true."
        ),
        "category_tags": [C.PET],
    },
    {
        "slug": "beach-summer-postcard",
        "display_name": "Summer Postcard",
        "prompt_text": (
            "Give this seaside photo a bright summer postcard look: turquoise water, clean "
            "white highlights and a deep blue sky, without changing the scene layout."
        ),
        "category_tags": [C.BEACH, C.LANDSCAPE],
    },
    {
        "slug": "sport-action-motion",
        "display_name": "Action Motion Blur",
        "prompt_text": (
            "Emphasise motion in this action shot with a subtle radial motion blur around the "
            "subject while keeping the subject crisp and unchanged."
        ),
        "category_tags": [C.SPORT],
    },
    {
        "slug": "watercolour-memory",
        "display_name": "Watercolour Memory",
        "prompt_text": (
            "Reinterpret this photo as a delicate watercolour painting with soft edges and "
            "visible paper texture, preserving the overall composition and the subjects."
        ),
        "category_tags": [C.OTHER, C.LANDSCAPE, C.PORTRAIT, C.GROUP_OF_FRIENDS],
    },
    {
        "slug": "clean-enhance",
        "display_name": "Clean Enhance",
        "prompt_text": (
            "Tastefully enhance this photo: balanced exposure, natural colour, gentle "
            "sharpening and noise reduction. Change nothing about the content."
        ),
        "category_tags": [C.OTHER],
    },
]

FALLBACK_TEMPLATE_SLUG = "clean-enhance"


def seed_prompt_templates(session: Session) -> int:
    """Insert any missing seed templates. Safe to run repeatedly."""
    existing = set(session.scalars(select(PromptTemplate.slug)).all())
    created = 0
    for template in SEED_TEMPLATES:
        if template["slug"] in existing:
            continue
        session.add(
            PromptTemplate(
                slug=template["slug"],
                display_name=template["display_name"],
                prompt_text=template["prompt_text"],
                category_tags=[tag.value for tag in template["category_tags"]],
                model_params=template.get("model_params", {}),
                source="curated",
            )
        )
        created += 1
    session.flush()
    return created
