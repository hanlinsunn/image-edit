import Foundation

/// Coarse location, derived on-device from an asset's coordinates. No raw
/// latitude/longitude is kept once features are built.
public struct CoarseLocation: Equatable, Sendable {
    public var type: LocationType
    /// Rounded grid cell used only for clustering photos taken near each other.
    public var gridKey: String?

    public init(type: LocationType, gridKey: String? = nil) {
        self.type = type
        self.gridKey = gridKey
    }

    public static let unknown = CoarseLocation(type: .unknown)
}

/// Everything the selection logic needs about a single asset. Produced by the
/// PhotoKit + Vision layer so that all ranking logic stays testable and
/// platform-agnostic.
public struct PhotoFeatures: Equatable, Sendable, Identifiable {
    public var id: String
    public var creationDate: Date
    public var isScreenshot: Bool
    public var isFavorite: Bool
    /// 0...1, higher is sharper.
    public var sharpness: Double
    /// 0...1 Vision aesthetics/quality score.
    public var aestheticScore: Double
    /// Fraction of the frame covered by detected text; receipts and documents are text heavy.
    public var textCoverage: Double
    public var faceCount: Int
    public var namedFaceIdentifiers: [String]
    /// Vision scene classification labels with confidence, best first.
    public var sceneLabels: [SceneLabel]
    public var location: CoarseLocation
    /// Perceptual hash used for near-duplicate detection.
    public var perceptualHash: UInt64

    public init(
        id: String,
        creationDate: Date,
        isScreenshot: Bool = false,
        isFavorite: Bool = false,
        sharpness: Double = 1,
        aestheticScore: Double = 0.5,
        textCoverage: Double = 0,
        faceCount: Int = 0,
        namedFaceIdentifiers: [String] = [],
        sceneLabels: [SceneLabel] = [],
        location: CoarseLocation = .unknown,
        perceptualHash: UInt64 = 0
    ) {
        self.id = id
        self.creationDate = creationDate
        self.isScreenshot = isScreenshot
        self.isFavorite = isFavorite
        self.sharpness = sharpness
        self.aestheticScore = aestheticScore
        self.textCoverage = textCoverage
        self.faceCount = faceCount
        self.namedFaceIdentifiers = namedFaceIdentifiers
        self.sceneLabels = sceneLabels
        self.location = location
        self.perceptualHash = perceptualHash
    }
}

public struct SceneLabel: Equatable, Sendable {
    public var identifier: String
    public var confidence: Double

    public init(identifier: String, confidence: Double) {
        self.identifier = identifier
        self.confidence = confidence
    }
}
