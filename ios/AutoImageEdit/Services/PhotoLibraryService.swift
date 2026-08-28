import CoreLocation
import Photos
import PhotoCuration
import UIKit

/// Reads the library with PhotoKit and turns each asset into platform-agnostic
/// `PhotoFeatures` via Vision. Nothing here leaves the device.
struct PhotoLibraryService {
    private let analyzer = VisionAnalyzer()
    private let imageManager = PHCachingImageManager()

    static func requestAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }

    /// Analyses the library newest-first. Screenshots are dropped before any image is
    /// decoded, which keeps a full-library scan affordable.
    func scanLibrary(
        limit: Int = 2_000,
        progress: @Sendable (Int, Int) -> Void = { _, _ in }
    ) async -> [PhotoFeatures] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(
            format: "mediaType == %d AND NOT ((mediaSubtypes & %d) != 0)",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaSubtype.photoScreenshot.rawValue
        )
        let assets = PHAsset.fetchAssets(with: options)

        var features: [PhotoFeatures] = []
        let total = min(limit, assets.count)
        for index in 0..<total {
            let asset = assets.object(at: index)
            if let analysed = await self.features(for: asset) {
                features.append(analysed)
            }
            progress(index + 1, total)
        }
        return features
    }

    func features(for asset: PHAsset) async -> PhotoFeatures? {
        guard let image = await thumbnail(for: asset, maxDimension: 512),
              let cgImage = image.cgImage
        else { return nil }

        let analysis = analyzer.analyze(cgImage)
        return PhotoFeatures(
            id: asset.localIdentifier,
            creationDate: asset.creationDate ?? Date.distantPast,
            isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
            isFavorite: asset.isFavorite,
            sharpness: analysis.sharpness,
            aestheticScore: analysis.aestheticScore,
            textCoverage: analysis.textCoverage,
            faceCount: analysis.faceCount,
            namedFaceIdentifiers: analysis.faceSignatures,
            sceneLabels: analysis.sceneLabels,
            location: Self.coarseLocation(for: asset.location),
            perceptualHash: PerceptualHash.difference(of: cgImage)
        )
    }

    func thumbnail(for asset: PHAsset, maxDimension: CGFloat) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        return await withCheckedContinuation { continuation in
            var resumed = false
            imageManager.requestImage(
                for: asset,
                targetSize: CGSize(width: maxDimension, height: maxDimension),
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !degraded, !resumed else { return }
                resumed = true
                continuation.resume(returning: image)
            }
        }
    }

    /// JPEG data for upload, capped so a batch stays small.
    func uploadData(for assetID: String, maxDimension: CGFloat = 1_536) async -> Data? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = assets.firstObject,
              let image = await thumbnail(for: asset, maxDimension: maxDimension)
        else { return nil }
        return image.jpegData(compressionQuality: 0.9)
    }

    /// Coordinates are reduced to a coarse type plus a ~11km grid cell used only for
    /// clustering; precise GPS never leaves the device.
    static func coarseLocation(for location: CLLocation?) -> CoarseLocation {
        guard let location else { return .unknown }
        let latitude = (location.coordinate.latitude * 10).rounded() / 10
        let longitude = (location.coordinate.longitude * 10).rounded() / 10
        return CoarseLocation(
            type: .unknown,
            gridKey: String(format: "%.1f,%.1f", latitude, longitude)
        )
    }
}
