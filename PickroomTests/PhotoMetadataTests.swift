import CoreGraphics
import XCTest
@testable import Pickroom

final class PhotoMetadataTests: XCTestCase {
    func testFormatsFastShutterSpeed() {
        var metadata = PhotoMetadata.placeholder(
            for: URL(fileURLWithPath: "/tmp/photo.dng"),
            isRaw: true
        )
        metadata.exposureTime = 1.0 / 500.0

        XCTAssertEqual(metadata.shutterDisplay, "1/500 s")
    }

    func testFormatsMegapixels() {
        var metadata = PhotoMetadata.placeholder(
            for: URL(fileURLWithPath: "/tmp/photo.arw"),
            isRaw: true
        )
        metadata.pixelWidth = 6_000
        metadata.pixelHeight = 4_000

        XCTAssertEqual(metadata.megapixelsDisplay, "24.0 MP")
    }

    func testCameraDisplayAvoidsDuplicatedMake() {
        var metadata = PhotoMetadata.placeholder(
            for: URL(fileURLWithPath: "/tmp/photo.nef"),
            isRaw: true
        )
        metadata.cameraMake = "NIKON"
        metadata.cameraModel = "NIKON Z 8"

        XCTAssertEqual(metadata.cameraDisplay, "NIKON Z 8")
    }

    func testFitPixelScaleUsesRetinaDisplayPixels() {
        let scale = ZoomMath.fitPixelScale(
            imageRect: CGRect(x: 0, y: 0, width: 500, height: 333),
            sourcePixelSize: CGSize(width: 4_000, height: 2_664),
            displayScale: 2
        )

        XCTAssertEqual(scale, 0.25, accuracy: 0.0001)
    }

    func testAnchoredZoomKeepsInspectedPointStationary() {
        let offset = ZoomMath.anchoredOffset(
            currentOffset: .zero,
            imageCenter: CGPoint(x: 500, y: 400),
            anchor: CGPoint(x: 750, y: 400),
            scaleRatio: 2
        )

        XCTAssertEqual(offset.width, -250, accuracy: 0.0001)
        XCTAssertEqual(offset.height, 0, accuracy: 0.0001)
    }

    func testZoomLabelsDistinguishFitActualSizeAndPercentage() {
        XCTAssertEqual(
            ZoomMath.displayLabel(zoomScale: 1, actualPixelScale: 0.25),
            "Fit"
        )
        XCTAssertEqual(
            ZoomMath.displayLabel(zoomScale: 4, actualPixelScale: 1),
            "1:1"
        )
        XCTAssertEqual(
            ZoomMath.displayLabel(zoomScale: 2, actualPixelScale: 0.5),
            "50%"
        )
    }

    @MainActor
    func testAppModelPreservesActualPixelScaleWhenFitScaleChanges() {
        let model = AppModel()
        model.updateFitPixelScale(0.25)
        model.zoomToActualSize()

        XCTAssertEqual(model.zoomScale, 4, accuracy: 0.0001)
        XCTAssertEqual(model.actualPixelScale, 1, accuracy: 0.0001)

        model.updateFitPixelScale(0.2)

        XCTAssertEqual(model.zoomScale, 5, accuracy: 0.0001)
        XCTAssertEqual(model.actualPixelScale, 1, accuracy: 0.0001)
        XCTAssertEqual(model.zoomDisplayLabel, "1:1")
    }

    func testReadsSVGDimensionsFromViewBox() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Pickroom-\(UUID().uuidString).svg")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(
            """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 450">
              <rect width="800" height="450" fill="#123456"/>
            </svg>
            """.utf8
        ).write(to: url)

        let metadata = MetadataReader.read(from: url, isRaw: false)

        XCTAssertEqual(metadata.pixelWidth, 800)
        XCTAssertEqual(metadata.pixelHeight, 450)
        XCTAssertEqual(metadata.decoderName, "AppKit SVG")
        XCTAssertEqual(metadata.megapixelsDisplay, "Vector")
    }

    func testRasterizesSVGPreviewAtRequestedLongEdge() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Pickroom-\(UUID().uuidString).svg")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(
            """
            <svg xmlns="http://www.w3.org/2000/svg" width="320" height="180">
              <rect width="320" height="180" fill="#123456"/>
              <circle cx="160" cy="90" r="50" fill="#ffcc00"/>
            </svg>
            """.utf8
        ).write(to: url)

        let loaded = await PreviewPipeline.shared.image(for: .file(url), maxPixelSize: 640)
        let preview = try XCTUnwrap(loaded)

        XCTAssertEqual(preview.cgImage.width, 640)
        XCTAssertEqual(preview.cgImage.height, 360)
    }
}
