import Foundation
import PhotoCuration
import SwiftUI

@MainActor
final class CandidateFeedViewModel: ObservableObject {
    @Published private(set) var candidates: [ScoredPhoto] = []
    @Published private(set) var excludedCount = 0
    @Published private(set) var scanProgress: Double?
    @Published private(set) var isUploading = false
    @Published var errorMessage: String?
    @Published var uploadedJobID: String?

    private let library = PhotoLibraryService()
    private let api: APIClient
    private let history = SelectionHistoryStore()

    init(api: APIClient = .shared) {
        self.api = api
    }

    func scan() async {
        scanProgress = 0
        let features = await library.scanLibrary { done, total in
            Task { @MainActor [weak self] in
                self?.scanProgress = total == 0 ? 1 : Double(done) / Double(total)
            }
        }
        let result = PhotoSelector.selectDailyBatch(
            from: features,
            referenceDate: Date(),
            history: history.load()
        )
        candidates = result.selected
        excludedCount = result.excluded.count
        scanProgress = nil
    }

    /// Uploads the selected photos and asks the backend to edit them.
    func uploadSelection() async {
        guard !candidates.isEmpty else { return }
        isUploading = true
        defer { isUploading = false }

        do {
            var payload: [IngestPhoto] = []
            for candidate in candidates.prefix(AppConfiguration.dailyBatchSize) {
                guard let data = await library.uploadData(for: candidate.photo.id) else { continue }
                payload.append(
                    IngestPhoto(
                        clientAssetId: candidate.photo.id,
                        contentType: "image/jpeg",
                        imageBase64: data.base64EncodedString(),
                        tags: candidate.tags
                    )
                )
            }
            let response = try await api.ingest(photos: payload)
            _ = try await api.runEdits(jobId: response.jobId)
            history.record(candidates)
            uploadedJobID = response.jobId
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Remembers what previous batches used so the next day avoids the same people and events.
struct SelectionHistoryStore {
    private let defaults = UserDefaults.standard
    private let photosKey = "history.photoIDs"
    private let clustersKey = "history.clusterIDs"
    private let facesKey = "history.faceIDs"
    private let limit = 200

    func load() -> SelectionHistory {
        SelectionHistory(
            usedPhotoIDs: Set(defaults.stringArray(forKey: photosKey) ?? []),
            usedClusterIDs: Set(defaults.stringArray(forKey: clustersKey) ?? []),
            usedFaceIdentifiers: Set(defaults.stringArray(forKey: facesKey) ?? [])
        )
    }

    func record(_ selected: [ScoredPhoto]) {
        let existing = load()
        store(existing.usedPhotoIDs.union(selected.map(\.photo.id)), key: photosKey)
        store(existing.usedClusterIDs.union(selected.map(\.clusterID)), key: clustersKey)
        store(
            existing.usedFaceIdentifiers.union(selected.flatMap(\.photo.namedFaceIdentifiers)),
            key: facesKey
        )
    }

    private func store(_ values: Set<String>, key: String) {
        defaults.set(Array(values.sorted().suffix(limit)), forKey: key)
    }
}
