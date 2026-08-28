import Foundation
import PhotoCuration

struct BackendUser: Decodable {
    let id: String
    let email: String?
    let timezone: String?
}

struct IngestPhoto: Encodable {
    let clientAssetId: String
    let contentType: String
    let imageBase64: String
    let tags: PhotoTags

    enum CodingKeys: String, CodingKey {
        case clientAssetId = "client_asset_id"
        case contentType = "content_type"
        case imageBase64 = "image_base64"
        case tags
    }
}

struct IngestResponse: Decodable {
    struct Accepted: Decodable {
        let photoId: String
        let clientAssetId: String

        enum CodingKeys: String, CodingKey {
            case photoId = "photo_id"
            case clientAssetId = "client_asset_id"
        }
    }

    let jobId: String
    let accepted: [Accepted]

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case accepted
    }
}

struct EditResultDTO: Decodable, Identifiable {
    let id: String
    let clientAssetId: String
    let templateSlug: String
    let templateDisplayName: String?
    let status: String
    let downloadUrl: String?
    let createdAt: Date
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case clientAssetId = "client_asset_id"
        case templateSlug = "template_slug"
        case templateDisplayName = "template_display_name"
        case status
        case downloadUrl = "download_url"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
}

struct PromptTemplateDTO: Decodable, Identifiable {
    let id: String
    let slug: String
    let displayName: String
    let categoryTags: [String]
    let exampleImageUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, slug
        case displayName = "display_name"
        case categoryTags = "category_tags"
        case exampleImageUrl = "example_image_url"
    }
}

enum APIError: LocalizedError {
    case notAuthenticated
    case http(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Sign in with Apple to continue."
        case .http(let status, let body):
            return "Server returned \(status): \(body)"
        }
    }
}

/// Thin HTTP/JSON client for the backend. Every call carries the Apple identity token.
final class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let credentials: CredentialStore
    private let decoder: JSONDecoder
    private let encoder = JSONEncoder()

    var baseURL: URL

    init(
        baseURL: URL = AppConfiguration.backendBaseURL,
        session: URLSession = .shared,
        credentials: CredentialStore = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
        self.credentials = credentials
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func createSession() async throws -> BackendUser {
        try await send(request(path: "/v1/auth/session", method: "POST"))
    }

    func templates() async throws -> [PromptTemplateDTO] {
        try await send(request(path: "/v1/templates", method: "GET"))
    }

    func results() async throws -> [EditResultDTO] {
        try await send(request(path: "/v1/results", method: "GET"))
    }

    func ingest(photos: [IngestPhoto]) async throws -> IngestResponse {
        var request = try request(path: "/v1/ingest", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(["photos": photos])
        return try await send(request)
    }

    func runEdits(jobId: String) async throws -> [EditResultDTO] {
        try await send(request(path: "/v1/jobs/\(jobId)/edits", method: "POST"))
    }

    func adHocEdit(photoId: String, templateSlug: String) async throws -> EditResultDTO {
        var request = try request(path: "/v1/edits/adhoc", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(
            ["photo_id": photoId, "template_slug": templateSlug]
        )
        return try await send(request)
    }

    func download(resultId: String) async throws -> Data {
        let (data, response) = try await session.data(
            for: try request(path: "/v1/results/\(resultId)/content", method: "GET")
        )
        try validate(response: response, data: data)
        return data
    }

    private func request(path: String, method: String) throws -> URLRequest {
        guard let token = credentials.identityToken else { throw APIError.notAuthenticated }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }
    }
}
