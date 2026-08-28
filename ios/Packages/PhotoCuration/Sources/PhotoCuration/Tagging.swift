import Foundation

/// Maps Vision scene classification labels and face counts onto the tag vocabulary
/// shared with the backend.
public enum PhotoTagger {
    static let sceneCategories: [String: PhotoCategory] = [
        "beach": .beach, "coast": .beach, "ocean": .beach, "sea": .beach,
        "mountain": .mountain, "valley": .mountain, "glacier": .mountain, "hiking": .mountain,
        "landscape": .landscape, "field": .landscape, "forest": .landscape, "lake": .landscape,
        "sunset": .landscape, "sunrise": .landscape, "desert": .landscape, "waterfall": .landscape,
        "skyline": .cityscape, "city": .cityscape, "street": .cityscape, "bridge": .cityscape,
        "building": .architecture, "church": .architecture, "castle": .architecture,
        "food": .food, "meal": .food, "restaurant": .food, "dessert": .food, "coffee": .food,
        "dog": .pet, "cat": .pet, "pet": .pet, "puppy": .pet, "kitten": .pet,
        "party": .celebration, "wedding": .celebration, "birthday": .celebration,
        "cake": .celebration, "concert": .nightlife, "bar": .nightlife, "nightclub": .nightlife,
        "ski": .sport, "surfing": .sport, "soccer": .sport, "basketball": .sport,
        "running": .sport, "bicycle": .sport
    ]

    public static func tags(
        for photo: PhotoFeatures,
        calendar: Calendar = .current
    ) -> PhotoTags {
        var categories = sceneDerivedCategories(photo)
        if photo.faceCount >= 3 {
            categories.insert(.groupOfFriends, at: 0)
        } else if photo.faceCount >= 1 {
            categories.insert(.portrait, at: categories.isEmpty ? 0 : 1)
        }

        let primary = categories.first ?? .other
        let secondary = Array(NSOrderedSet(array: categories.dropFirst().map { $0.rawValue }))
            .compactMap { $0 as? String }
            .compactMap(PhotoCategory.init(rawValue:))

        return PhotoTags(
            primaryCategory: primary,
            secondaryCategories: secondary,
            peopleCount: photo.faceCount,
            namedFaceCount: photo.namedFaceIdentifiers.count,
            timeOfDay: timeOfDay(for: photo.creationDate, calendar: calendar),
            season: season(for: photo.creationDate, calendar: calendar),
            locationType: photo.location.type,
            isFavorite: photo.isFavorite,
            aestheticScore: photo.aestheticScore
        )
    }

    static func sceneDerivedCategories(_ photo: PhotoFeatures) -> [PhotoCategory] {
        var seen: [PhotoCategory] = []
        for label in photo.sceneLabels.sorted(by: { $0.confidence > $1.confidence })
        where label.confidence >= 0.3 {
            let key = label.identifier.lowercased()
            guard let category = sceneCategories.first(where: { key.contains($0.key) })?.value
            else { continue }
            if !seen.contains(category) { seen.append(category) }
        }
        return seen
    }

    static func timeOfDay(for date: Date, calendar: Calendar) -> TimeOfDay {
        switch calendar.component(.hour, from: date) {
        case 5..<12: return .morning
        case 12..<17: return .afternoon
        case 17..<20: return .goldenHour
        default: return .night
        }
    }

    static func season(for date: Date, calendar: Calendar) -> Season {
        switch calendar.component(.month, from: date) {
        case 3...5: return .spring
        case 6...8: return .summer
        case 9...11: return .autumn
        default: return .winter
        }
    }
}
