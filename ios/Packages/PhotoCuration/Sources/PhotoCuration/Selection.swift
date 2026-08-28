import Foundation

/// What previous days already used, so a batch does not repeat the same people or events.
public struct SelectionHistory: Equatable, Sendable {
    public var usedPhotoIDs: Set<String>
    public var usedClusterIDs: Set<String>
    public var usedFaceIdentifiers: Set<String>

    public init(
        usedPhotoIDs: Set<String> = [],
        usedClusterIDs: Set<String> = [],
        usedFaceIdentifiers: Set<String> = []
    ) {
        self.usedPhotoIDs = usedPhotoIDs
        self.usedClusterIDs = usedClusterIDs
        self.usedFaceIdentifiers = usedFaceIdentifiers
    }

    public static let empty = SelectionHistory()
}

public struct SelectionOptions {
    public var batchSize: Int
    public var weights: ScoringWeights
    public var thresholds: FilterThresholds
    /// How strongly a cluster or face already used on a previous day is penalised.
    public var repeatPenalty: Double
    public var calendar: Calendar

    public init(
        batchSize: Int = 5,
        weights: ScoringWeights = .default,
        thresholds: FilterThresholds = .default,
        repeatPenalty: Double = 3.0,
        calendar: Calendar = .current
    ) {
        self.batchSize = batchSize
        self.weights = weights
        self.thresholds = thresholds
        self.repeatPenalty = repeatPenalty
        self.calendar = calendar
    }

    public static let `default` = SelectionOptions()
}

public struct SelectionResult: Equatable, Sendable {
    public var selected: [ScoredPhoto]
    /// Everything that survived filtering, best first — powers the local candidate feed.
    public var ranked: [ScoredPhoto]
    public var excluded: [String: ExclusionReason]

    public init(
        selected: [ScoredPhoto],
        ranked: [ScoredPhoto],
        excluded: [String: ExclusionReason]
    ) {
        self.selected = selected
        self.ranked = ranked
        self.excluded = excluded
    }
}

/// The end-to-end on-device pipeline: filter, cluster, tag, score, then pick a
/// diverse daily batch.
public enum PhotoSelector {
    public static func selectDailyBatch(
        from photos: [PhotoFeatures],
        referenceDate: Date,
        history: SelectionHistory = .empty,
        options: SelectionOptions = .default
    ) -> SelectionResult {
        let filtered = PhotoFilter.apply(to: photos, thresholds: options.thresholds)
        let clusters = PhotoClusterer.cluster(filtered.kept)

        var scored: [ScoredPhoto] = []
        for cluster in clusters {
            for photo in cluster.photos where !history.usedPhotoIDs.contains(photo.id) {
                let tags = PhotoTagger.tags(for: photo, calendar: options.calendar)
                var value = PhotoScorer.score(
                    photo: photo,
                    tags: tags,
                    referenceDate: referenceDate,
                    weights: options.weights,
                    calendar: options.calendar
                )
                if history.usedClusterIDs.contains(cluster.id) {
                    value -= options.repeatPenalty
                }
                if !history.usedFaceIdentifiers.isDisjoint(with: photo.namedFaceIdentifiers) {
                    value -= options.repeatPenalty
                }
                scored.append(
                    ScoredPhoto(photo: photo, tags: tags, score: value, clusterID: cluster.id)
                )
            }
        }

        let ranked = scored.sorted(by: betterFirst)
        return SelectionResult(
            selected: pickDiverse(from: ranked, options: options),
            ranked: ranked,
            excluded: filtered.excluded
        )
    }

    /// At most one photo per cluster and per named person until the batch cannot be
    /// filled any other way.
    static func pickDiverse(
        from ranked: [ScoredPhoto],
        options: SelectionOptions
    ) -> [ScoredPhoto] {
        var selected: [ScoredPhoto] = []
        var clusters: Set<String> = []
        var faces: Set<String> = []

        for candidate in ranked where selected.count < options.batchSize {
            let repeatedFace = !faces.isDisjoint(with: candidate.photo.namedFaceIdentifiers)
            guard !clusters.contains(candidate.clusterID), !repeatedFace else { continue }
            selected.append(candidate)
            clusters.insert(candidate.clusterID)
            faces.formUnion(candidate.photo.namedFaceIdentifiers)
        }

        if selected.count < options.batchSize {
            let chosen = Set(selected.map(\.id))
            for candidate in ranked
            where selected.count < options.batchSize && !chosen.contains(candidate.id) {
                selected.append(candidate)
            }
        }
        return selected
    }

    static func betterFirst(_ lhs: ScoredPhoto, _ rhs: ScoredPhoto) -> Bool {
        if lhs.score == rhs.score { return lhs.id < rhs.id }
        return lhs.score > rhs.score
    }
}
