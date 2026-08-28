import Foundation
import SwiftUI

@MainActor
final class ResultsViewModel: ObservableObject {
    @Published private(set) var results: [EditResultDTO] = []
    @Published private(set) var templates: [PromptTemplateDTO] = []
    @Published private(set) var images: [String: UIImage] = [:]
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let results = api.results()
            async let templates = api.templates()
            self.results = try await results
            self.templates = try await templates
            for result in self.results where images[result.id] == nil {
                await loadImage(for: result)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyTemplate(_ slug: String, toPhotoID photoID: String) async {
        do {
            let result = try await api.adHocEdit(photoId: photoID, templateSlug: slug)
            results.insert(result, at: 0)
            await loadImage(for: result)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadImage(for result: EditResultDTO) async {
        guard result.status == "ready" else { return }
        do {
            let data = try await api.download(resultId: result.id)
            images[result.id] = UIImage(data: data)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
