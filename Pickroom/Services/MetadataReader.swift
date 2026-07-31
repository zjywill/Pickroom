import Foundation
import ImageIO
import RawEngine

enum MetadataReader {
    static func read(from url: URL, isRaw: Bool) -> PhotoMetadata {
        read(
            from: url,
            isRaw: isRaw,
            imageIOProperties: imageIOProperties(from: url)
        )
    }

    static func read(
        from url: URL,
        isRaw: Bool,
        imageIOProperties properties: [CFString: Any]?
    ) -> PhotoMetadata {
        var metadata = PhotoMetadata.placeholder(for: url, isRaw: isRaw)

        if let values = try? url.resourceValues(forKeys: [.fileSizeKey]) {
            metadata.fileSize = values.fileSize.map(Int64.init)
        }

        if let properties {
            metadata.pixelWidth = number(properties[kCGImagePropertyPixelWidth])?.intValue
            metadata.pixelHeight = number(properties[kCGImagePropertyPixelHeight])?.intValue

            let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
            let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]

            metadata.cameraMake = string(tiff?[kCGImagePropertyTIFFMake])
            metadata.cameraModel = string(tiff?[kCGImagePropertyTIFFModel])
            metadata.lensModel = string(exif?[kCGImagePropertyExifLensModel])
            metadata.focalLength = number(exif?[kCGImagePropertyExifFocalLength])?.doubleValue
            metadata.aperture = number(exif?[kCGImagePropertyExifFNumber])?.doubleValue
            metadata.exposureTime = number(exif?[kCGImagePropertyExifExposureTime])?.doubleValue
            metadata.capturedAt = string(exif?[kCGImagePropertyExifDateTimeOriginal])

            if let ratings = exif?[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber] {
                metadata.iso = ratings.first?.intValue
            } else {
                metadata.iso = number(exif?[kCGImagePropertyExifISOSpeed])?.intValue
            }
        }

        if SVGSupport.isSVG(url) {
            if let dimensions = SVGSupport.dimensions(from: url) {
                metadata.pixelWidth = Int(dimensions.width.rounded())
                metadata.pixelHeight = Int(dimensions.height.rounded())
            }
            metadata.decoderName = "AppKit SVG"
        } else if isRaw {
            mergeLibRawMetadata(into: &metadata, from: url)
        } else {
            metadata.decoderName = "ImageIO"
        }

        return metadata
    }

    private static func imageIOProperties(from url: URL) -> [CFString: Any]? {
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
            return nil
        }

        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    }

    private static func mergeLibRawMetadata(into metadata: inout PhotoMetadata, from url: URL) {
        guard let raw = try? RawDecoder.metadata(from: url) else {
            metadata.decoderName = "System RAW"
            return
        }

        metadata.pixelWidth = raw.width ?? metadata.pixelWidth
        metadata.pixelHeight = raw.height ?? metadata.pixelHeight
        metadata.cameraMake = raw.cameraMake ?? metadata.cameraMake
        metadata.cameraModel = raw.cameraModel ?? metadata.cameraModel
        metadata.lensModel = raw.lensModel ?? metadata.lensModel
        metadata.focalLength = raw.focalLength ?? metadata.focalLength
        metadata.aperture = raw.aperture ?? metadata.aperture
        metadata.exposureTime = raw.shutter ?? metadata.exposureTime
        metadata.iso = raw.iso ?? metadata.iso
        if metadata.capturedAt == nil, let capturedAt = raw.capturedAt {
            metadata.capturedAt = capturedAt.formatted(
                date: .abbreviated,
                time: .shortened
            )
        }
        metadata.decoderName = "LibRaw \(RawDecoder.version)"
    }

    private static func number(_ value: Any?) -> NSNumber? {
        value as? NSNumber
    }

    private static func string(_ value: Any?) -> String? {
        value as? String
    }
}
