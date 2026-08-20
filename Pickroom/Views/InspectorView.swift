import AppKit
import SwiftUI

struct InspectorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let asset = model.currentAsset {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        InspectorHeader(asset: asset)

                        InspectorSection("Review") {
                            DecisionPicker()
                        }

                        InspectorSection("Capture") {
                            MetadataRow("Shutter", value: asset.metadata.shutterDisplay)
                            MetadataRow("Aperture", value: asset.metadata.apertureDisplay)
                            MetadataRow("ISO", value: asset.metadata.isoDisplay)
                            MetadataRow("Focal length", value: asset.metadata.focalLengthDisplay)
                        }

                        InspectorSection("Camera") {
                            MetadataRow("Body", value: asset.metadata.cameraDisplay)
                            MetadataRow("Lens", value: asset.metadata.lensDisplay)
                        }

                        InspectorSection("Location") {
                            MetadataRow("Place", value: asset.metadata.locationDisplay)
                            LocationButton(asset: asset)
                        }

                        InspectorSection("Image") {
                            MetadataRow("Dimensions", value: asset.metadata.dimensionsDisplay)
                            MetadataRow("Resolution", value: asset.metadata.megapixelsDisplay)
                            MetadataRow("Format", value: asset.metadata.fileExtension)
                            MetadataRow("File size", value: asset.metadata.fileSizeDisplay)
                            if let capturedAt = asset.metadata.capturedAt {
                                MetadataRow("Captured", value: capturedAt)
                            }
                        }

                        InspectorSection("Composition") {
                            InspectorToggle(
                                title: "Thirds grid",
                                subtitle: "Check balance and subject placement",
                                symbol: "grid",
                                isOn: Binding(
                                    get: { model.compositionGridEnabled },
                                    set: { model.compositionGridEnabled = $0 }
                                )
                            )
                        }
                    }
                    .padding(18)
                }
            } else {
                InspectorPlaceholder()
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Inspector")
    }
}

private struct InspectorHeader: View {
    let asset: PhotoAsset

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(
                    asset.metadata.isRaw ? "RAW" : asset.metadata.fileExtension,
                    systemImage: asset.metadata.isRaw ? "camera" : "photo"
                )
                .font(.caption.weight(.bold))
                .foregroundStyle(.tint)

                Spacer()

                if asset.companionURL != nil {
                    Label("Paired", systemImage: "link")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if asset.isArchived {
                    Label("Collected", systemImage: "archivebox.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if asset.needsOriginalDownload {
                    Label("iCloud", systemImage: "icloud")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("The original is not on this Mac yet.")
                }
            }

            Text(asset.filename)
                .font(.headline)
                .lineLimit(2)
                .truncationMode(.middle)

            Text(locationDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Label(asset.metadata.decoderName, systemImage: "cpu")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var locationDescription: String {
        if let url = asset.fileURL {
            return url.deletingLastPathComponent().path
        }
        return asset.downloadedOriginalURL == nil
            ? "Photos Library"
            : "Photos Library · original downloaded"
    }
}

private struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            content
        }
    }
}

/// Opens the map, or explains why it cannot be opened for this photo.
///
/// Both refusals are worth spelling out. A Photos library picture is not a
/// file Pickroom can write beside, and an SVG has nowhere to put coordinates
/// — neither is a bug, and a greyed-out button with no reason reads like one.
private struct LocationButton: View {
    @Environment(AppModel.self) private var model
    let asset: PhotoAsset

    private var refusal: String? {
        guard asset.fileURL == nil else {
            return (try? PhotoLocationWriter.target(for: asset)) == nil
                ? "\(asset.metadata.fileExtension) files have nowhere to store a location."
                : nil
        }
        return "Photos library pictures keep the location your camera recorded."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                model.beginChoosingLocation()
            } label: {
                Label(
                    asset.metadata.location == nil ? "Set Location…" : "Change Location…",
                    systemImage: "mappin.and.ellipse"
                )
            }
            .disabled(refusal != nil || model.isLoading || model.isTaggingLocation)

            if asset.metadata.location != nil {
                Button("Remove Location", role: .destructive) {
                    model.requestLocationClear(scope: model.defaultLocationScope)
                }
                .disabled(model.isLoading || model.isTaggingLocation)
            }

            if let refusal {
                Text(refusal)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DecisionPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Picker("Decision", selection: Binding(
            get: { model.currentAsset?.decision ?? .unreviewed },
            set: { model.setDecision($0, advance: false) }
        )) {
            ForEach(PhotoDecision.allCases, id: \.self) { decision in
                Label(decision.shortTitle, systemImage: decision.symbol)
                    .tag(decision)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InspectorPlaceholder: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "sidebar.right")
                .font(.title3)
                .foregroundStyle(.tertiary)

            Text("Select a photo")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)

            Text("Capture details will appear here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct MetadataRow: View {
    let label: String
    let value: String

    init(_ label: String, value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .monospacedDigit()
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
    }
}

private struct InspectorToggle: View {
    let title: String
    let subtitle: String
    let symbol: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: symbol)
                    .frame(width: 18)
            }

            Spacer(minLength: 12)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(title)
        }
        .frame(maxWidth: .infinity)
    }
}
