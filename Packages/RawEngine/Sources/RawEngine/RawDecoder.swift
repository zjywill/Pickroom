import CoreGraphics
import Foundation
import ImageIO
import CRawEngine

public struct RawMetadata: Sendable {
    public let cameraMake: String?
    public let cameraModel: String?
    public let lensModel: String?
    public let width: Int?
    public let height: Int?
    public let iso: Int?
    public let shutter: Double?
    public let aperture: Double?
    public let focalLength: Double?
    public let capturedAt: Date?
}

public struct RawDecodedImage: Sendable {
    public enum Format: Int, Sendable {
        case jpeg = 1
        case bitmap = 2
        case jpegXL = 3
        case unknown = 0
    }

    public let data: Data
    public let width: Int
    public let height: Int
    public let bitsPerSample: Int
    public let components: Int
    public let format: Format

    public func cgImage() -> CGImage? {
        if format == .jpeg || format == .jpegXL || format == .unknown {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                return nil
            }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }

        let bytesPerComponent = max(bitsPerSample / 8, 1)
        let bytesPerRow = width * components * bytesPerComponent
        guard
            data.count >= height * bytesPerRow,
            let provider = CGDataProvider(data: data as CFData),
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        else {
            return nil
        }

        var bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        if bitsPerSample == 16 {
            bitmapInfo.insert(.byteOrder16Little)
        }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: bitsPerSample,
            bitsPerPixel: bitsPerSample * components,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}

public enum RawDecoderError: LocalizedError {
    case failed(code: Int32, message: String)
    case invalidPayload

    public var errorDescription: String? {
        switch self {
        case .failed(_, let message):
            message
        case .invalidPayload:
            "LibRaw returned an invalid image payload."
        }
    }
}

public enum RawDecoder {
    public static var version: String {
        String(cString: pr_raw_version())
    }

    public static func metadata(from url: URL) throws -> RawMetadata {
        var rawMetadata = PRRawMetadata()
        let result = url.path.withCString {
            pr_raw_read_metadata($0, &rawMetadata)
        }
        defer {
            pr_raw_free_metadata(&rawMetadata)
        }

        guard result == 0 else {
            throw error(for: result)
        }

        return RawMetadata(
            cameraMake: string(rawMetadata.make),
            cameraModel: string(rawMetadata.model),
            lensModel: string(rawMetadata.lens),
            width: positive(Int(rawMetadata.width)),
            height: positive(Int(rawMetadata.height)),
            iso: positive(Int(rawMetadata.iso.rounded())),
            shutter: positive(rawMetadata.shutter),
            aperture: positive(rawMetadata.aperture),
            focalLength: positive(rawMetadata.focal_length),
            capturedAt: rawMetadata.timestamp > 0
                ? Date(timeIntervalSince1970: TimeInterval(rawMetadata.timestamp))
                : nil
        )
    }

    public static func thumbnail(from url: URL) throws -> RawDecodedImage {
        try decode(url: url, operation: pr_raw_extract_thumbnail)
    }

    public static func preview(from url: URL, halfSize: Bool = true) throws -> RawDecodedImage {
        var image = PRRawImage()
        let result = url.path.withCString {
            pr_raw_render_preview($0, halfSize ? 1 : 0, &image)
        }
        defer {
            pr_raw_free_image(&image)
        }

        guard result == 0 else {
            throw error(for: result)
        }
        return try decodedImage(from: image)
    }

    private static func decode(
        url: URL,
        operation: (UnsafePointer<CChar>?, UnsafeMutablePointer<PRRawImage>?) -> Int32
    ) throws -> RawDecodedImage {
        var image = PRRawImage()
        let result = url.path.withCString {
            operation($0, &image)
        }
        defer {
            pr_raw_free_image(&image)
        }

        guard result == 0 else {
            throw error(for: result)
        }
        return try decodedImage(from: image)
    }

    private static func decodedImage(from image: PRRawImage) throws -> RawDecodedImage {
        guard
            let bytes = image.bytes,
            image.byte_count > 0,
            image.width > 0,
            image.height > 0
        else {
            throw RawDecoderError.invalidPayload
        }

        return RawDecodedImage(
            data: Data(bytes: bytes, count: image.byte_count),
            width: Int(image.width),
            height: Int(image.height),
            bitsPerSample: Int(image.bits_per_sample),
            components: Int(image.components),
            format: RawDecodedImage.Format(rawValue: Int(image.format)) ?? .unknown
        )
    }

    private static func error(for code: Int32) -> RawDecoderError {
        let message = pr_raw_error_message(code).map(String.init(cString:))
            ?? "Unknown LibRaw error"
        return .failed(code: code, message: message)
    }

    private static func string(_ value: UnsafeMutablePointer<CChar>?) -> String? {
        guard let value else { return nil }
        let result = String(cString: value)
        return result.isEmpty ? nil : result
    }

    private static func positive<T: BinaryInteger>(_ value: T) -> T? {
        value > 0 ? value : nil
    }

    private static func positive<T: BinaryFloatingPoint>(_ value: T) -> T? {
        value > 0 ? value : nil
    }
}
