import Foundation

/// Version of the tag vocabulary shared with the backend (`backend/app/tags.py`).
public let tagVocabularyVersion = 1

public enum PhotoCategory: String, Codable, CaseIterable, Sendable {
    case groupOfFriends = "group_of_friends"
    case portrait
    case landscape
    case cityscape
    case beach
    case mountain
    case food
    case pet
    case nightlife
    case architecture
    case sport
    case celebration
    case other
}

public enum TimeOfDay: String, Codable, Sendable {
    case morning, afternoon, goldenHour = "golden_hour", night
}

public enum Season: String, Codable, Sendable {
    case spring, summer, autumn, winter
}

/// Deliberately coarse: precise coordinates never leave the device.
public enum LocationType: String, Codable, Sendable {
    case homeArea = "home_area"
    case city, nature, coast, abroad, unknown
}

/// Lightweight metadata uploaded alongside a selected photo.
public struct PhotoTags: Codable, Equatable, Sendable {
    public var primaryCategory: PhotoCategory
    public var secondaryCategories: [PhotoCategory]
    public var peopleCount: Int
    public var namedFaceCount: Int
    public var timeOfDay: TimeOfDay?
    public var season: Season?
    public var locationType: LocationType
    public var isFavorite: Bool
    public var aestheticScore: Double
    public var vocabularyVersion: Int

    public init(
        primaryCategory: PhotoCategory,
        secondaryCategories: [PhotoCategory] = [],
        peopleCount: Int = 0,
        namedFaceCount: Int = 0,
        timeOfDay: TimeOfDay? = nil,
        season: Season? = nil,
        locationType: LocationType = .unknown,
        isFavorite: Bool = false,
        aestheticScore: Double = 0,
        vocabularyVersion: Int = tagVocabularyVersion
    ) {
        self.primaryCategory = primaryCategory
        self.secondaryCategories = secondaryCategories
        self.peopleCount = peopleCount
        self.namedFaceCount = namedFaceCount
        self.timeOfDay = timeOfDay
        self.season = season
        self.locationType = locationType
        self.isFavorite = isFavorite
        self.aestheticScore = aestheticScore
        self.vocabularyVersion = vocabularyVersion
    }

    enum CodingKeys: String, CodingKey {
        case primaryCategory = "primary_category"
        case secondaryCategories = "secondary_categories"
        case peopleCount = "people_count"
        case namedFaceCount = "named_face_count"
        case timeOfDay = "time_of_day"
        case season
        case locationType = "location_type"
        case isFavorite = "is_favorite"
        case aestheticScore = "aesthetic_score"
        case vocabularyVersion = "vocabulary_version"
    }
}
