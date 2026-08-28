from app.schemas import PhotoTags
from app.services.matching import match_template
from app.services.prompts import FALLBACK_TEMPLATE_SLUG
from app.tags import PhotoCategory


def tags(primary: PhotoCategory, secondary: list[PhotoCategory] | None = None) -> PhotoTags:
    return PhotoTags(primary_category=primary, secondary_categories=secondary or [])


def test_matches_landscape_to_landscape_template(db):
    match = match_template(db, tags(PhotoCategory.LANDSCAPE))
    assert not match.is_fallback
    assert PhotoCategory.LANDSCAPE.value in match.template.category_tags


def test_matches_group_photo_to_group_template(db):
    match = match_template(db, tags(PhotoCategory.GROUP_OF_FRIENDS, [PhotoCategory.CELEBRATION]))
    assert match.template.slug == "friends-confetti-party"


def test_matches_food_and_pet_categories(db):
    assert match_template(db, tags(PhotoCategory.FOOD)).template.slug == "food-magazine-shot"
    assert match_template(db, tags(PhotoCategory.PET)).template.slug == "pet-portrait-hero"


def test_recently_used_templates_are_penalised(db):
    first = match_template(db, tags(PhotoCategory.LANDSCAPE)).template.slug
    second = match_template(db, tags(PhotoCategory.LANDSCAPE), recently_used={first}).template.slug
    assert second != first


def test_unmatched_category_falls_back(db):
    match = match_template(db, tags(PhotoCategory.OTHER))
    assert match.template.slug == FALLBACK_TEMPLATE_SLUG


def test_matching_is_deterministic(db):
    picks = {match_template(db, tags(PhotoCategory.CITYSCAPE)).template.slug for _ in range(5)}
    assert len(picks) == 1
