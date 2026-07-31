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
                            RatingPicker(rating: asset.rating)
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
            }

            Text(asset.filename)
                .font(.headline)
                .lineLimit(2)
                .truncationMode(.middle)

            Text(asset.url.deletingLastPathComponent().path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Label(asset.metadata.decoderName, systemImage: "cpu")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
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

private struct RatingPicker: View {
    @Environment(AppModel.self) private var model
    let rating: Int

    var body: some View {
        RatingLevelIndicator(
            rating: Binding(
                get: { model.currentAsset?.rating ?? rating },
                set: { model.setRating($0) }
            )
        )
        .frame(height: 32)
        .fixedSize(horizontal: true, vertical: false)
        .help("Drag to set a rating from zero to five stars")
    }
}

private struct RatingLevelIndicator: NSViewRepresentable {
    @Binding var rating: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSLevelIndicator {
        let indicator = NSLevelIndicator()
        indicator.levelIndicatorStyle = .rating
        indicator.minValue = 0
        indicator.maxValue = 5
        indicator.doubleValue = Double(rating)
        indicator.isEditable = true
        indicator.isContinuous = true
        indicator.placeholderVisibility = .always
        indicator.fillColor = .systemYellow
        let symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: 19,
            weight: .regular
        )
        indicator.ratingImage = NSImage(
            systemSymbolName: "star.fill",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(symbolConfiguration)
        indicator.ratingPlaceholderImage = NSImage(
            systemSymbolName: "star",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(symbolConfiguration)
        indicator.target = context.coordinator
        indicator.action = #selector(Coordinator.ratingChanged(_:))
        indicator.setAccessibilityLabel("Photo rating")
        return indicator
    }

    func updateNSView(_ indicator: NSLevelIndicator, context: Context) {
        context.coordinator.parent = self
        let newValue = Double(rating)
        if indicator.doubleValue != newValue {
            indicator.doubleValue = newValue
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: RatingLevelIndicator

        init(_ parent: RatingLevelIndicator) {
            self.parent = parent
        }

        @objc
        func ratingChanged(_ sender: NSLevelIndicator) {
            parent.rating = min(max(Int(sender.doubleValue.rounded()), 0), 5)
        }
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
