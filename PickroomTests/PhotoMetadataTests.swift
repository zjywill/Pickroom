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
}
