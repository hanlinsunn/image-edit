import SwiftUI

@main
struct AutoImageEditApp: App {
    @StateObject private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        switch session.stage {
        case .signedOut:
            SignInView()
        case .needsPhotoAccess:
            PermissionPrimingView()
        case .ready:
            MainTabView()
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            CandidateFeedView()
                .tabItem { Label("Today", systemImage: "sparkles") }
            ResultsView()
                .tabItem { Label("Edits", systemImage: "wand.and.stars") }
        }
    }
}
