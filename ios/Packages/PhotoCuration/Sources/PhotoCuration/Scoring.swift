import Foundation

/// User-tunable weights driving which photos are worth resurfacing.
public struct ScoringWeights: Equatable, Sendable {
    public var aesthetics: Double
    public var friends: Double
    public var landscape: Double
    public var funMemory: Double
    public var favorite: Double
    public var namedFace: Double
    public var thisWeekInPriorYears: Double
    public var recency: Double

    public init(
        aesthetics: Double = 2.0,
        friends: Double = 2.5,
        landscape: Double = 1.8,
        funMemory: Double = 1.5,
        favorite: Double = 1.2,
        namedFace: Double = 0.8,
        thisWeekInPriorYears: Double = 2.0,
        recency: Double = 0.5
    ) {
        self.aesthetics = aesthetics
        self.friends = friends
        self.landscape = landscape
        self.funMemory = funMemory
        self.favorite = favorite
        self.namedFace = namedFace
        self.thisWeekInPriorYears = thisWeekInPriorYears
        self.recency = recency
    }

    public static let `default` = ScoringWeights()
}

public struct ScoredPhoto: Equatable, Sendable, Identifiable {
    public var id: String { photo.id }
    public var photo: PhotoFeatures
    public var tags: PhotoTags
    public var score: Double
    public var clusterID: String

    public init(photo: PhotoFeatures, tags: PhotoTags, score: Double, clusterID: String) {
        self.photo = photo
        self.tags = tags
        self.score = score
        self.clusterID = clusterID
    }
}

public enum PhotoScorer {
    static let funCategories: Set<PhotoCategory> = [
        .celebration, .nightlife, .sport, .pet, .food, .beach
    ]
    static let landscapeCategories: Set<PhotoCategory> = [
        .landscape, .mountain, .beach, .cityscape
    ]

    public static func score(
        photo: PhotoFeatures,
        tags: PhotoTags,
        referenceDate: Date,
        weights: ScoringWeights = .default,
        calendar: Calendar = .current
    ) -> Double {
        var score = weights.aesthetics * photo.aestheticScore

        let categories = Set([tags.primaryCategory] + tags.secondaryCategories)
        if categories.contains(.groupOfFriends) {
            score += weights.friends
        }
        if !categories.isDisjoint(with: landscapeCategories) {
            score += weights.landscape
        }
        if !categories.isDisjoint(with: funCategories) {
            score += weights.funMemory
        }
        if photo.isFavorite {
            score += weights.favorite
        }
        score += weights.namedFace * min(Double(photo.namedFaceIdentifiers.count), 3) / 3

        if isThisWeekInPriorYear(photo.creationDate, reference: referenceDate, calendar: calendar) {
            score += weights.thisWeekInPriorYears
        }
        score += weights.recency * recencyFactor(photo.creationDate, reference: referenceDate)
        return score
    }

    /// Same week of the year, but not the current year.
    static func isThisWeekInPriorYear(
        _ date: Date,
        reference: Date,
        calendar: Calendar
    ) -> Bool {
        let photo = calendar.dateComponents([.year, .weekOfYear], from: date)
        let now = calendar.dateComponents([.year, .weekOfYear], from: reference)
        guard let photoYear = photo.year, let nowYear = now.year else { return false }
        return photoYear < nowYear && photo.weekOfYear == now.weekOfYear
    }

    /// Decays over roughly a decade so old photos still surface, just less often.
    static func recencyFactor(_ date: Date, reference: Date) -> Double {
        let years = reference.timeIntervalSince(date) / (365 * 24 * 3600)
        return max(0, 1 - years / 10)
    }
}
