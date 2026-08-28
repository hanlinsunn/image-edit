import AuthenticationServices
import Foundation
import Photos

enum SessionStage {
    case signedOut
    case needsPhotoAccess
    case ready
}

/// Owns identity (Sign in with Apple) and photo-library authorization, which together
/// decide which screen the app shows.
@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var stage: SessionStage = .signedOut
    @Published private(set) var user: BackendUser?
    @Published var errorMessage: String?

    private let credentials: CredentialStore
    private let api: APIClient

    init(credentials: CredentialStore = .shared, api: APIClient = .shared) {
        self.credentials = credentials
        self.api = api
        refreshStage()
    }

    func handleSignIn(result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let token = String(data: tokenData, encoding: .utf8)
            else {
                errorMessage = "Apple did not return an identity token."
                return
            }
            credentials.identityToken = token
            Task { await loadUser() }
        }
    }

    func loadUser() async {
        do {
            user = try await api.createSession()
            refreshStage()
        } catch {
            errorMessage = error.localizedDescription
            credentials.identityToken = nil
            refreshStage()
        }
    }

    func requestPhotoAccess() async {
        let status = await PhotoLibraryService.requestAuthorization()
        if status != .authorized {
            errorMessage = "Full photo access is needed to find photos worth resurfacing."
        }
        refreshStage()
    }

    func signOut() {
        credentials.identityToken = nil
        user = nil
        refreshStage()
    }

    private func refreshStage() {
        guard credentials.identityToken != nil else {
            stage = .signedOut
            return
        }
        stage = PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized
            ? .ready
            : .needsPhotoAccess
    }
}
