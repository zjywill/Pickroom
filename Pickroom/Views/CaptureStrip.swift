import SwiftUI

struct CaptureStrip: View {
    let asset: PhotoAsset

    var body: some View {
        HStack(spacing: 0) {
            CaptureValue(
                label: "Shutter",
                value: asset.metadata.shutterDisplay,
                symbol: "camera.shutter.button"
            )
            CaptureValue(
                label: "Aperture",
                value: asset.metadata.apertureDisplay,
                symbol: "camera.aperture"
            )
            CaptureValue(
                label: "Sensitivity",
                value: asset.metadata.isoDisplay,
                symbol: "circle.lefthalf.filled"
            )
            CaptureValue(
                label: "Focal length",
                value: asset.metadata.focalLengthDisplay,
                symbol: "scope"
            )

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                Text(asset.metadata.cameraDisplay)
                    .font(.caption.weight(.medium))
                Text(asset.metadata.lensDisplay)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

private struct CaptureValue: View {
    let label: String
    let value: String
    let symbol: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 120, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value)")
    }
}
