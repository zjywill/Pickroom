import AppKit
import Foundation

enum SVGSupport {
    static func isSVG(_ url: URL) -> Bool {
        url.pathExtension.caseInsensitiveCompare("svg") == .orderedSame
    }

    static func dimensions(from url: URL) -> CGSize? {
        guard
            let parser = XMLParser(contentsOf: url)
        else {
            return nil
        }

        let delegate = SVGRootElementParser()
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        _ = parser.parse()
        return delegate.dimensions
    }

    static func rasterizedImage(for url: URL, maxPixelSize: Int) -> CGImage? {
        guard
            isSVG(url),
            maxPixelSize > 0,
            let image = NSImage(contentsOf: url)
        else {
            return nil
        }

        let intrinsicSize = dimensions(from: url) ?? image.size
        let longEdge = max(intrinsicSize.width, intrinsicSize.height)
        guard longEdge > 0 else { return nil }

        let scale = CGFloat(maxPixelSize) / longEdge
        let pixelWidth = max(Int((intrinsicSize.width * scale).rounded()), 1)
        let pixelHeight = max(Int((intrinsicSize.height * scale).rounded()), 1)

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        bitmap.size = NSSize(width: pixelWidth, height: pixelHeight)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return nil
        }

        context.imageInterpolation = .high
        NSGraphicsContext.current = context
        image.draw(
            in: NSRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        context.flushGraphics()
        return bitmap.cgImage
    }
}

private final class SVGRootElementParser: NSObject, XMLParserDelegate {
    private(set) var dimensions: CGSize?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard dimensions == nil, elementName.caseInsensitiveCompare("svg") == .orderedSame else {
            return
        }

        let width = Self.length(attributeDict["width"])
        let height = Self.length(attributeDict["height"])
        let viewBox = Self.viewBox(attributeDict["viewBox"])

        switch (width, height, viewBox) {
        case let (width?, height?, _):
            dimensions = CGSize(width: width, height: height)
        case let (width?, nil, viewBox?) where viewBox.width > 0:
            dimensions = CGSize(
                width: width,
                height: width * viewBox.height / viewBox.width
            )
        case let (nil, height?, viewBox?) where viewBox.height > 0:
            dimensions = CGSize(
                width: height * viewBox.width / viewBox.height,
                height: height
            )
        case let (_, _, viewBox?):
            dimensions = viewBox
        default:
            break
        }
    }

    private static func length(_ value: String?) -> CGFloat? {
        guard let value else { return nil }

        let scanner = Scanner(string: value.trimmingCharacters(in: .whitespacesAndNewlines))
        scanner.locale = Locale(identifier: "en_US_POSIX")
        guard let number = scanner.scanDouble(), number > 0 else { return nil }

        let unit = String(scanner.string[scanner.currentIndex...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let multiplier: Double
        switch unit {
        case "", "px":
            multiplier = 1
        case "pt":
            multiplier = 96 / 72
        case "pc":
            multiplier = 16
        case "in":
            multiplier = 96
        case "cm":
            multiplier = 96 / 2.54
        case "mm":
            multiplier = 96 / 25.4
        case "q":
            multiplier = 96 / 101.6
        default:
            return nil
        }

        return CGFloat(number * multiplier)
    }

    private static func viewBox(_ value: String?) -> CGSize? {
        guard let value else { return nil }

        let components = value
            .split { $0 == " " || $0 == "," || $0 == "\n" || $0 == "\t" }
            .compactMap { Double($0) }
        guard components.count == 4, components[2] > 0, components[3] > 0 else {
            return nil
        }

        return CGSize(width: components[2], height: components[3])
    }
}
