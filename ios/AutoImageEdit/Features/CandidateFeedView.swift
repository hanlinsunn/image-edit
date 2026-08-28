import PhotoCuration
import Photos
import SwiftUI

struct CandidateFeedView: View {
    @StateObject private var model = CandidateFeedViewModel()

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if let progress = model.scanProgress {
                    ProgressView("Scanning your library", value: progress)
                        .padding(32)
                } else if model.candidates.isEmpty {
                    ContentUnavailableView(
                        "Nothing selected yet",
                        systemImage: "photo.stack",
                        description: Text("Scan your library to find today's photos.")
                    )
                } else {
                    grid
                }
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Scan") { Task { await model.scan() } }
                }
            }
            .safeAreaInset(edge: .bottom) { uploadBar }
            .task { if model.candidates.isEmpty { await model.scan() } }
            .alert(
                "Something went wrong",
                isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: { if !$0 { model.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(model.candidates) { candidate in
                    VStack(alignment: .leading, spacing: 6) {
                        AssetThumbnail(assetID: candidate.photo.id)
                            .frame(height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        Text(candidate.tags.primaryCategory.rawValue.replacingOccurrences(
                            of: "_", with: " "
                        ))
                        .font(.caption.bold())
                        Text(candidate.photo.creationDate, style: .date)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
            if model.excludedCount > 0 {
                Text("\(model.excludedCount) photos skipped (screenshots, documents, blurry, duplicates)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 16)
            }
        }
    }

    @ViewBuilder
    private var uploadBar: some View {
        if !model.candidates.isEmpty {
            Button {
                Task { await model.uploadSelection() }
            } label: {
                if model.isUploading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Upload & edit \(model.candidates.count) photos")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isUploading)
            .padding(16)
            .background(.bar)
        }
    }
}

/// Loads a PhotoKit thumbnail for a local identifier.
struct AssetThumbnail: View {
    let assetID: String
    @State private var image: UIImage?

    private let library = PhotoLibraryService()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.secondary.opacity(0.15)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .task {
                let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
                guard let asset = assets.firstObject else { return }
                image = await library.thumbnail(for: asset, maxDimension: proxy.size.width * 2)
            }
        }
    }
}
