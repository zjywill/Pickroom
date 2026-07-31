import Foundation

struct PhotoMetadata: Codable, Hashable, Sendable {
    var pixelWidth: Int?
    var pixelHeight: Int?
    var cameraMake: String?
    var cameraModel: String?
    var lensModel: String?
    var focalLength: Double?
    var aperture: Double?
    var exposureTime: Double?
    var iso: Int?
    var capturedAt: String?
    var fileSize: Int64?
    var fileExtension: String
    var isRaw: Bool
    var decoderName: String

    static func placeholder(for url: URL, isRaw: Bool) -> PhotoMetadata {
        PhotoMetadata(
            pixelWidth: nil,
            pixelHeight: nil,
            cameraMake: nil,
            cameraModel: nil,
            lensModel: nil,
            focalLength: nil,
            aperture: nil,
            exposureTime: nil,
            iso: nil,
            capturedAt: nil,
            fileSize: nil,
            fileExtension: url.pathExtension.uppercased(),
            isRaw: isRaw,
            decoderName: isRaw ? "RAW decoder pending" : "ImageIO"
        )
    }

    var shutterDisplay: String {
        guard let exposureTime, exposureTime > 0 else { return "—" }
        if exposureTime >= 1 {
            return exposureTime.formatted(.number.precision(.fractionLength(0...1))) + " s"
        }

        let denominator = Int((1 / exposureTime).rounded())
        return "1/\(max(denominator, 1)) s"
    }

    var apertureDisplay: String {
        guard let aperture else { return "—" }
        return "f/" + aperture.formatted(.number.precision(.fractionLength(0...1)))
    }

    var isoDisplay: String {
        guard let iso else { return "—" }
        return "ISO \(iso)"
    }

    var focalLengthDisplay: String {
        guard let focalLength else { return "—" }
        return focalLength.formatted(.number.precision(.fractionLength(0...1))) + " mm"
    }

    var dimensionsDisplay: String {
        guard let pixelWidth, let pixelHeight else { return "—" }
        return "\(pixelWidth) × \(pixelHeight)"
    }

    var megapixelsDisplay: String {
        if fileExtension.caseInsensitiveCompare("SVG") == .orderedSame {
            return "Vector"
        }
        guard let pixelWidth, let pixelHeight else { return "—" }
        let megapixels = Double(pixelWidth * pixelHeight) / 1_000_000
        return megapixels.formatted(.number.precision(.fractionLength(1))) + " MP"
    }

    var cameraDisplay: String {
        let values = [cameraMake, cameraModel]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !values.isEmpty else { return "Unknown camera" }
        if values.count == 2, values[1].localizedCaseInsensitiveContains(values[0]) {
            return values[1]
        }
        return values.joined(separator: " ")
    }

    var lensDisplay: String {
        guard let lensModel, !lensModel.isEmpty else { return "Unknown lens" }
        return lensModel
    }

    var fileSizeDisplay: String {
        guard let fileSize else { return "—" }
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}
