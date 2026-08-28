import SwiftUI

struct ResultsView: View {
    @StateObject private var model = ResultsViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if model.results.isEmpty {
                    ContentUnavailableView(
                        "No edits yet",
                        systemImage: "wand.and.stars",
                        description: Text("Upload today's photos to see edited versions here.")
                    )
                } else {
                    List(model.results) { result in
                        ResultRow(result: result, image: model.images[result.id])
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Edits")
            .refreshable { await model.refresh() }
            .task { await model.refresh() }
            .overlay { if model.isLoading && model.results.isEmpty { ProgressView() } }
        }
    }
}

struct ResultRow: View {
    let result: EditResultDTO
    let image: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.secondary.opacity(0.15))
                    .frame(height: 220)
                    .overlay { ProgressView() }
            }
            HStack {
                VStack(alignment: .leading) {
                    Text(result.templateDisplayName ?? result.templateSlug).font(.headline)
                    Text("Available until \(result.expiresAt, style: .date)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let image {
                    ShareLink(
                        item: Image(uiImage: image),
                        preview: SharePreview(
                            result.templateDisplayName ?? "Edited photo",
                            image: Image(uiImage: image)
                        )
                    )
                }
            }
        }
        .padding(.vertical, 8)
    }
}

/// Curated template picker used for ad-hoc edits (no freeform prompts in v1).
struct TemplatePicker: View {
    let templates: [PromptTemplateDTO]
    let onSelect: (String) -> Void

    var body: some View {
        List(templates) { template in
            Button(template.displayName) { onSelect(template.slug) }
        }
        .navigationTitle("Choose a style")
    }
}
