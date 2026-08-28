"""Shared photo tag vocabulary.

The iOS client derives these tags on-device and sends them alongside the selected
photos. The prompt library is tagged with the same vocabulary so a photo can be
matched to a category-appropriate editing prompt. Bump ``TAG_VOCABULARY_VERSION``
whenever a category is added or removed so clients and server stay in sync.
"""

from enum import Enum

TAG_VOCABULARY_VERSION = 1


class PhotoCategory(str, Enum):
    GROUP_OF_FRIENDS = "group_of_friends"
    PORTRAIT = "portrait"
    LANDSCAPE = "landscape"
    CITYSCAPE = "cityscape"
    BEACH = "beach"
    MOUNTAIN = "mountain"
    FOOD = "food"
    PET = "pet"
    NIGHTLIFE = "nightlife"
    ARCHITECTURE = "architecture"
    SPORT = "sport"
    CELEBRATION = "celebration"
    OTHER = "other"


class TimeOfDay(str, Enum):
    MORNING = "morning"
    AFTERNOON = "afternoon"
    GOLDEN_HOUR = "golden_hour"
    NIGHT = "night"


class Season(str, Enum):
    SPRING = "spring"
    SUMMER = "summer"
    AUTUMN = "autumn"
    WINTER = "winter"


class LocationType(str, Enum):
    """Coarse location bucket. Precise coordinates never leave the device."""

    HOME_AREA = "home_area"
    CITY = "city"
    NATURE = "nature"
    COAST = "coast"
    ABROAD = "abroad"
    UNKNOWN = "unknown"
