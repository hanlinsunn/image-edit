import Foundation

/// A trip or event: photos taken close together in time, and in the same coarse place.
public struct PhotoCluster: Equatable, Sendable, Identifiable {
    public var id: String
    public var photos: [PhotoFeatures]

    public var startDate: Date { photos.first?.creationDate ?? .distantPast }
    public var endDate: Date { photos.last?.creationDate ?? .distantPast }

    public init(id: String, photos: [PhotoFeatures]) {
        self.id = id
        self.photos = photos
    }
}

public enum PhotoClusterer {
    /// Groups chronologically: a new cluster starts when the time gap exceeds
    /// `maximumGap` or the coarse location grid cell changes.
    public static func cluster(
        _ photos: [PhotoFeatures],
        maximumGap: TimeInterval = 6 * 3600
    ) -> [PhotoCluster] {
        let ordered = photos.sorted { $0.creationDate < $1.creationDate }
        var clusters: [PhotoCluster] = []
        var current: [PhotoFeatures] = []

        for photo in ordered {
            guard let previous = current.last else {
                current = [photo]
                continue
            }
            let gap = photo.creationDate.timeIntervalSince(previous.creationDate)
            let movedAway = gridKeysDiffer(previous.location.gridKey, photo.location.gridKey)
            if gap > maximumGap || movedAway {
                clusters.append(PhotoCluster(id: current[0].id, photos: current))
                current = [photo]
            } else {
                current.append(photo)
            }
        }
        if !current.isEmpty {
            clusters.append(PhotoCluster(id: current[0].id, photos: current))
        }
        return clusters
    }

    /// Unknown locations never split a cluster; only two known, different cells do.
    private static func gridKeysDiffer(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs else { return false }
        return lhs != rhs
    }
}
