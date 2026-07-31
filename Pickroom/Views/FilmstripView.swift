import SwiftUI

struct FilmstripView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 8) {
                    ForEach(model.filteredAssets) { asset in
                        FilmstripThumbnail(
                            asset: asset,
                            isSelected: asset.id == model.currentAssetID
                        ) {
                            model.select(asset)
                        }
                        .id(asset.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .frame(height: 82)
            .background(Color(nsColor: .controlBackgroundColor))
            .onChange(of: model.currentAssetID) { _, newID in
                guard let newID else { return }
                proxy.scrollTo(newID, anchor: .center)
            }
        }
    }
}

private struct FilmstripThumbnail: View {
    let asset: PhotoAsset
    let isSelected: Bool
    let action: () -> Void

    @State private var preview: PreviewImage?

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Color.black

                    if let preview {
                        Image(decorative: preview.cgImage, scale: 1, orientation: .up)
                            .resizable()
                            .scaledToFit()
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .frame(width: 86, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                if asset.decision != .unreviewed {
                    Image(systemName: asset.decision.symbol)
                        .font(.caption)
                        .foregroundStyle(asset.decision.tint)
                        .padding(4)
                        .background(.black.opacity(0.72), in: Circle())
                        .padding(4)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.white.opacity(0.12),
                        lineWidth: isSelected ? 3 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .help(asset.filename)
        .accessibilityLabel(asset.filename)
        .accessibilityValue("\(asset.decision.title), \(asset.rating) stars")
        .task(id: asset.url) {
            preview = await PreviewPipeline.shared.image(
                for: asset.url,
                maxPixelSize: 260,
                priority: .background
            )
        }
    }
}
