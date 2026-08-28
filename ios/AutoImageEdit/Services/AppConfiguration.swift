import Foundation

enum AppConfiguration {
    /// Overridable from the scheme (`BACKEND_BASE_URL`) so the app can point at a
    /// laptop running `uvicorn` during development.
    static var backendBaseURL: URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "BackendBaseURL") as? String,
           let url = URL(string: raw), !raw.isEmpty {
            return url
        }
        if let raw = ProcessInfo.processInfo.environment["BACKEND_BASE_URL"],
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "http://localhost:8000")!
    }

    static let dailyBatchSize = 5
}
