import SwiftUI

/// Shown before the system prompt so App Review — and the user — see exactly why
/// full library access is required and what leaves the device.
struct PermissionPrimingView: View {
    @EnvironmentObject private var session: SessionStore

    private let points: [(String, String, String)] = [
        (
            "photo.on.rectangle.angled",
            "We look at your whole library",
            "Finding forgotten favourites needs more than a hand-picked selection."
        ),
        (
            "iphone.gen3",
            "Analysis happens on your iPhone",
            "Faces, scenes and quality are scored on-device with Apple Vision."
        ),
        (
            "lock.shield",
            "Only five photos a day are uploaded",
            "Just the photos chosen for editing leave your device — never your location."
        ),
        (
            "trash",
            "Originals are deleted right after editing",
            "Edited results are kept for 30 days, then removed automatically."
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Allow access to your photos")
                .font(.largeTitle.bold())
            ForEach(points, id: \.1) { point in
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: point.0)
                        .font(.title2)
                        .frame(width: 32)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(point.1).font(.headline)
                        Text(point.2).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if let message = session.errorMessage {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
            Button {
                Task { await session.requestPhotoAccess() }
            } label: {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
    }
}
