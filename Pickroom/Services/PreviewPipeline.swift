import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import RawEngine

struct PreviewImage: @unchecked Sendable {
    let cgImage: CGImage
}

enum PreviewPriority {
    case foreground
    case background
}

final class PreviewPipeline: @unchecked Sendable {
    static let shared = PreviewPipeline()

    private let cache = NSCache<NSString, CGImage>()
    private let cacheLock = NSLock()
    private var cachedSizes: [String: Set<Int>] = [:]
    private let context = CIContext(options: [
        .cacheIntermediates: false,
        .priorityRequestLow: false
    ])
    private let foregroundQueue = DispatchQueue(
        label: "com.junyizhang.Pickroom.preview.foreground",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private let backgroundQueue = DispatchQueue(
        label: "com.junyizhang.Pickroom.preview.background",
        qos: .utility,
        attributes: .concurrent
    )
    private let foregroundSlots = DispatchSemaphore(value: 2)
    private let backgroundSlots = DispatchSemaphore(value: 2)

    private init() {
        cache.countLimit = 160
        cache.totalCostLimit = 512 * 1_024 * 1_024
    }

    func cachedImage(for url: URL) -> PreviewImage? {
        let path = url.standardizedFileURL.path
        cacheLock.lock()
        let sizes = cachedSizes[path]?.sorted(by: >) ?? []
        cacheLock.unlock()

        for size in sizes {
            let key = cacheKey(path: path, maxPixelSize: size)
            if let image = cache.object(forKey: key as NSString) {
                return PreviewImage(cgImage: image)
            }
        }
        return nil
    }

    func image(
        for url: URL,
        maxPixelSize: Int,
        priority: PreviewPriority = .foreground
    ) async -> PreviewImage? {
        let path = url.standardizedFileURL.path
        let key = cacheKey(path: path, maxPixelSize: maxPixelSize)
        if let cached = cache.object(forKey: key as NSString) {
            return PreviewImage(cgImage: cached)
        }

        let queue = priority == .foreground ? foregroundQueue : backgroundQueue
        let slots = priority == .foreground ? foregroundSlots : backgroundSlots

        return await withCheckedContinuation { continuation in
            queue.async { [self] in
                slots.wait()
                defer { slots.signal() }

                if let cached = cache.object(forKey: key as NSString) {
                    continuation.resume(returning: PreviewImage(cgImage: cached))
                    return
                }

                let image = decodeImage(for: url, maxPixelSize: maxPixelSize)
                if let image {
                    store(image, path: path, maxPixelSize: maxPixelSize)
                    continuation.resume(returning: PreviewImage(cgImage: image))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func decodeImage(for url: URL, maxPixelSize: Int) -> CGImage? {
        if SVGSupport.isSVG(url) {
            return SVGSupport.rasterizedImage(
                for: url,
                maxPixelSize: maxPixelSize
            )
        }

        if let image = imageIOPreview(for: url, maxPixelSize: maxPixelSize) {
            let longEdge = max(image.width, image.height)
            if !PhotoLibraryScanner.isRaw(url)
                || longEdge >= minimumPreviewLongEdge(for: maxPixelSize) {
                return image
            }
        }

        if PhotoLibraryScanner.isRaw(url),
           let image = libRawPreview(for: url, maxPixelSize: maxPixelSize) {
            return image
        }

        if let image = coreImagePreview(for: url, maxPixelSize: maxPixelSize) {
            return image
        }

        return nil
    }

    private func store(_ image: CGImage, path: String, maxPixelSize: Int) {
        let key = cacheKey(path: path, maxPixelSize: maxPixelSize)
        let cost = image.bytesPerRow * image.height
        cache.setObject(image, forKey: key as NSString, cost: cost)

        cacheLock.lock()
        cachedSizes[path, default: []].insert(maxPixelSize)
        cacheLock.unlock()
    }

    private func cacheKey(path: String, maxPixelSize: Int) -> String {
        "\(path)#\(maxPixelSize)"
    }

    private func minimumPreviewLongEdge(for maxPixelSize: Int) -> Int {
        if maxPixelSize <= 800 {
            return max(maxPixelSize / 2, 120)
        }
        if maxPixelSize > 3_200 {
            return maxPixelSize * 9 / 10
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
