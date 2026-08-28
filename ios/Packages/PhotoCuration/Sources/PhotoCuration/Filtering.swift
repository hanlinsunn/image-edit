import Foundation

public enum ExclusionReason: String, Equatable, Sendable {
    case screenshot
    case documentOrReceipt
    case blurry
    case lowQuality
    case duplicate
}

public struct FilterThresholds: Sendable {
    public var minimumSharpness: Double
    public var maximumTextCoverage: Double
    public var minimumAestheticScore: Double
    /// Maximum Hamming distance between perceptual hashes still counted as a duplicate.
    public var duplicateHashDistance: Int

    public init(
        minimumSharpness: Double = 0.35,
        maximumTextCoverage: Double = 0.18,
        minimumAestheticScore: Double = 0.25,
        duplicateHashDistance: Int = 6
    ) {
        self.minimumSharpness = minimumSharpness
        self.maximumTextCoverage = maximumTextCoverage
        self.minimumAestheticScore = minimumAestheticScore
        self.duplicateHashDistance = duplicateHashDistance
    }

    public static let `default` = FilterThresholds()
}

public struct FilterOutcome: Equatable, Sendable {
    public var kept: [PhotoFeatures]
    public var excluded: [String: ExclusionReason]

    public init(kept: [PhotoFeatures], excluded: [String: ExclusionReason]) {
        self.kept = kept
        self.excluded = excluded
    }
}

public enum PhotoFilter {
    /// Drops screenshots, documents/receipts, blurry and low quality frames, then keeps
    /// only the best representative of each near-duplicate group.
    public static func apply(
        to photos: [PhotoFeatures],
        thresholds: FilterThresholds = .default
    ) -> FilterOutcome {
        var excluded: [String: ExclusionReason] = [:]
        var survivors: [PhotoFeatures] = []

        for photo in photos {
            if let reason = reject(photo, thresholds: thresholds) {
                excluded[photo.id] = reason
            } else {
                survivors.append(photo)
            }
        }

        var kept: [PhotoFeatures] = []
        for photo in survivors.sorted(by: qualityDescending) {
            if let twin = kept.first(where: {
                hammingDistance($0.perceptualHash, photo.perceptualHash)
                    <= thresholds.duplicateHashDistance
            }) {
                _ = twin
                excluded[photo.id] = .duplicate
            } else {
                kept.append(photo)
            }
        }

        return FilterOutcome(
            kept: kept.sorted { $0.creationDate < $1.creationDate },
            excluded: excluded
        )
    }

    private static func reject(
        _ photo: PhotoFeatures,
        thresholds: FilterThresholds
    ) -> ExclusionReason? {
        if photo.isScreenshot { return .screenshot }
        if photo.textCoverage > thresholds.maximumTextCoverage { return .documentOrReceipt }
        if photo.sharpness < thresholds.minimumSharpness { return .blurry }
        if photo.aestheticScore < thresholds.minimumAestheticScore { return .lowQuality }
        return nil
    }

    private static func qualityDescending(_ lhs: PhotoFeatures, _ rhs: PhotoFeatures) -> Bool {
        let left = lhs.aestheticScore + (lhs.isFavorite ? 1 : 0)
        let right = rhs.aestheticScore + (rhs.isFavorite ? 1 : 0)
        if left == right { return lhs.id < rhs.id }
        return left > right
    }

    public static func hammingDistance(_ lhs: UInt64, _ rhs: UInt64) -> Int {
        (lhs ^ rhs).nonzeroBitCount
    }
}
