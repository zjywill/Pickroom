import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import RawEngine

struct PreviewImage: @unchecked Sendable {
    let cgImage: CGImage
}

actor PreviewPipeline {
    static let shared = PreviewPipeline()

    private let cache = NSCache<NSString, CGImage>()
    private let context = CIContext(options: [
        .cacheIntermediates: false,
        .priorityRequestLow: false
    ])

    func image(for url: URL, maxPixelSize: Int) -> PreviewImage? {
        let cacheKey = "\(url.standardizedFileURL.path)#\(maxPixelSize)" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return PreviewImage(cgImage: cached)
        }

        if let image = imageIOPreview(for: url, maxPixelSize: maxPixelSize) {
            let longEdge = max(image.width, image.height)
            if !PhotoLibraryScanner.isRaw(url)
                || longEdge >= minimumPreviewLongEdge(for: maxPixelSize) {
                cache.setObject(image, forKey: cacheKey)
                return PreviewImage(cgImage: image)
            }
        }

        if PhotoLibraryScanner.isRaw(url),
           let image = libRawPreview(for: url, maxPixelSize: maxPixelSize) {
            cache.setObject(image, forKey: cacheKey)
            return PreviewImage(cgImage: image)
        }

        if let image = coreImagePreview(for: url, maxPixelSize: maxPixelSize) {
            cache.setObject(image, forKey: cacheKey)
            return PreviewImage(cgImage: image)
        }

        return nil
    }

    private func minimumPreviewLongEdge(for maxPixelSize: Int) -> Int {
        if maxPixelSize <= 800 {
            return max(maxPixelSize / 2, 120)
        }
        return min(maxPixelSize * 3 / 4, 2_400)
    }

    private func imageIOPreview(for url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private func coreImagePreview(for url: URL, maxPixelSize: Int) -> CGImage? {
        guard let input = CIImage(
            contentsOf: url,
            options: [
                .applyOrientationProperty: true,
                .cacheImmediately: false
            ]
        ) else {
            return nil
        }

        let longEdge = max(input.extent.width, input.extent.height)
        let scale = longEdge > CGFloat(maxPixelSize) ? CGFloat(maxPixelSize) / longEdge : 1
        let output = scale < 1
            ? input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            : input

        return context.createCGImage(output, from: output.extent)
    }

    private func libRawPreview(for url: URL, maxPixelSize: Int) -> CGImage? {
        if let thumbnail = try? RawDecoder.thumbnail(from: url),
           let image = thumbnail.cgImage(),
           max(image.width, image.height) >= minimumPreviewLongEdge(for: maxPixelSize) {
            return scaled(image, maxPixelSize: maxPixelSize)
        }

        guard
            let preview = try? RawDecoder.preview(
                from: url,
                halfSize: maxPixelSize <= 3_200
            ),
            let image = preview.cgImage()
        else {
            return nil
        }

        return scaled(image, maxPixelSize: maxPixelSize)
    }

    private func scaled(_ image: CGImage, maxPixelSize: Int) -> CGImage {
        let longEdge = max(image.width, image.height)
        guard longEdge > maxPixelSize else { return image }

        let scale = CGFloat(maxPixelSize) / CGFloat(longEdge)
        let ciImage = CIImage(cgImage: image)
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return context.createCGImage(ciImage, from: ciImage.extent) ?? image
    }
}
