import SwiftUI

struct PhotoGridView: View {
    @Environment(AppModel.self) private var model

    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 14)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(model.filteredAssets) { asset in
                    PhotoGridTile(
                        asset: asset,
                        isSelected: asset.id == model.currentAssetID
                    ) {
                        model.select(asset)
                    } open: {
                        model.select(asset)
                        model.workspaceMode = .cull
                    }
                }
            }
            .padding(18)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct PhotoGridTile: View {
    @Environment(AppModel.self) private var model
    let asset: PhotoAsset
    let isSelected: Bool
    let select: () -> Void
    let open: () -> Void

    @State private var preview: PreviewImage?

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        PickroomColors.canvas

                        if let preview {
                            Image(decorative: preview.cgImage, scale: 1, orientation: .up)
                                .resizable()
                                .scaledToFit()
                                .padding(4)
                        } else {
                            ProgressView()
                        }
                    }
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    if asset.decision != .unreviewed {
                        Label(asset.decision.shortTitle, systemImage: asset.decision.symbol)
                            .labelStyle(.iconOnly)
                            .font(.title3)
                            .foregroundStyle(asset.decision.tint)
                            .padding(7)
                            .background(.black.opacity(0.70), in: Circle())
                            .padding(8)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.primary.opacity(0.10),
                            lineWidth: isSelected ? 3 : 1
                        )
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(asset.filename)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text([
                            asset.metadata.shutterDisplay,
                            asset.metadata.apertureDisplay,
                            asset.metadata.isoDisplay
                        ].joined(separator: "  "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    if asset.rating > 0 {
                        Label("\(asset.rating)", systemImage: "star.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.yellow)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded(open)
        )
        .contextMenu {
            Button("Pick") {
                select()
                model.setDecision(.pick, advance: false)
            }
            Button("Maybe") {
                select()
                model.setDecision(.maybe, advance: false)
            }
            Button("Reject") {
                select()
                model.setDecision(.reject, advance: false)
            }
            Divider()
            Button("Unmark") {
                select()
                model.setDecision(.unreviewed, advance: false)
            }
        }
        .task(id: asset.url) {
            preview = await PreviewPipeline.shared.image(for: asset.url, maxPixelSize: 720)
        }
        .accessibilityLabel(asset.filename)
        .accessibilityValue("\(asset.decision.title), \(asset.rating) stars")
        .accessibilityHint("Double-click to open culling view")
    }
}
