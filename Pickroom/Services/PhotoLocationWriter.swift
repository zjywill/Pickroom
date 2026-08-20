import Foundation
import ImageIO
import UniformTypeIdentifiers

enum LocationWriteError: LocalizedError, Equatable {
    case photosLibraryAsset
    case unsupportedFormat(String)
    case malformedSidecar(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .photosLibraryAsset:
            "Photos library pictures already carry the location your camera "
                + "or phone recorded, and Pickroom cannot add one without "
                + "editing the library itself."
        case .unsupportedFormat(let ext):
            "Pickroom cannot store a location in a \(ext) file."
        case .malformedSidecar(let name):
            "“\(name)” is not a sidecar Pickroom can edit. Move it aside and try again."
        case .writeFailed(let name):
            "“\(name)” could not be written. Check that it is not read-only."
        }
    }
}

/// Where a given photo's coordinates have to go.
enum LocationTarget: Equatable {
    /// Proprietary RAW: an `.xmp` beside the original, which stays untouched.
    case sidecar(URL)
    /// A format ImageIO can rewrite, so the coordinates go in the file itself.
    case inPlace(URL)
}

/// Routes a location to the only place each format can hold it, and puts it there.
enum PhotoLocationWriter {
    /// Formats ImageIO rewrites without re-encoding the picture.
    ///
    /// DNG is here rather than with the RAW files on purpose: it is a raw
    /// format, but an open one that Adobe treats as writable, and Lightroom
    /// ignores a sidecar next to a DNG.
    static let inPlaceExtensions: Set<String> = [
        "dng", "heic", "heif", "jpeg", "jpg", "png", "tif", "tiff"
    ]

    static func target(for asset: PhotoAsset) throws -> LocationTarget {
        guard let url = asset.fileURL else {
            throw LocationWriteError.photosLibraryAsset
        }
        return try target(for: url)
    }

    static func target(for url: URL) throws -> LocationTarget {
        let ext = url.pathExtension.lowercased()

        if inPlaceExtensions.contains(ext) {
            return .inPlace(url)
        }
        if PhotoLibraryScanner.isRaw(url) {
            return .sidecar(LocationSidecar.url(for: url))
        }
        throw LocationWriteError.unsupportedFormat(ext.uppercased())
    }

    static func canWrite(_ asset: PhotoAsset) -> Bool {
        (try? target(for: asset)) != nil
    }

    static func write(_ location: PhotoLocation, to url: URL) throws {
        switch try target(for: url) {
        case .sidecar:
            try LocationSidecar.write(location, for: url)
        case .inPlace:
            try writeInPlace(location, to: url)
        }
    }

    /// Reads whatever location the photo already has.
    ///
    /// The sidecar wins over the file for RAW: if both carry coordinates, the
    /// sidecar is the edit and the file is what the camera happened to record.
    static func read(from url: URL) -> PhotoLocation? {
        if case .sidecar = try? target(for: url), let sidecar = LocationSidecar.read(for: url) {
            return sidecar
        }
        guard
            let source = CGImageSourceCreateWithURL(
                url as CFURL,
                [kCGImageSourceShouldCache: false] as CFDictionary
            ),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return nil
        }
        return location(fromGPS: properties[kCGImagePropertyGPSDictionary] as? [CFString: Any])
    }

    static func location(fromGPS gps: [CFString: Any]?) -> PhotoLocation? {
        guard
            let gps,
            let latitude = (gps[kCGImagePropertyGPSLatitude] as? NSNumber)?.doubleValue,
            let longitude = (gps[kCGImagePropertyGPSLongitude] as? NSNumber)?.doubleValue
        else {
            return nil
        }

        let latitudeRef = gps[kCGImagePropertyGPSLatitudeRef] as? String
        let longitudeRef = gps[kCGImagePropertyGPSLongitudeRef] as? String

        return PhotoLocation(
            latitude: latitudeRef == "S" ? -latitude : latitude,
            longitude: longitudeRef == "W" ? -longitude : longitude
        )
    }

    // MARK: - In-place

    /// Replaces the GPS block and copies everything else across untouched.
    ///
    /// `CGImageDestinationAddImageFromSource` hands the destination the
    /// original compressed data rather than a decoded bitmap, so a JPEG comes
    /// out with the pixels it went in with — no generational loss from
    /// tagging a photo, and no loss from tagging it a second time.
    private static func writeInPlace(_ location: PhotoLocation, to url: URL) throws {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let type = CGImageSourceGetType(source)
        else {
            throw LocationWriteError.writeFailed(url.lastPathComponent)
        }

        var properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
            as? [CFString: Any] ?? [:]
        properties[kCGImagePropertyGPSDictionary] = gpsDictionary(for: location)

        let temporaryURL = url
            .deletingLastPathComponent()
            .appendingPathComponent(".pickroom-\(UUID().uuidString).tmp")

        guard
            let destination = CGImageDestinationCreateWithURL(
                temporaryURL as CFURL,
                type,
                1,
                nil
            )
        else {
            throw LocationWriteError.writeFailed(url.lastPathComponent)
        }

        CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw LocationWriteError.writeFailed(url.lastPathComponent)
        }

        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw LocationWriteError.writeFailed(url.lastPathComponent)
        }
    }

    private static func gpsDictionary(for location: PhotoLocation) -> [CFString: Any] {
        // EXIF stores the magnitude and puts the sign in a separate reference
        // field, so a negative latitude here would be silently wrong.
        [
            kCGImagePropertyGPSLatitude: abs(location.latitude),
            kCGImagePropertyGPSLatitudeRef: GPSCoordinateFormat.hemisphere(
                for: location.latitude,
                isLatitude: true
            ),
            kCGImagePropertyGPSLongitude: abs(location.longitude),
            kCGImagePropertyGPSLongitudeRef: GPSCoordinateFormat.hemisphere(
                for: location.longitude,
                isLatitude: false
            ),
            kCGImagePropertyGPSVersion: "2.2.0.0"
        ]
    }
}
