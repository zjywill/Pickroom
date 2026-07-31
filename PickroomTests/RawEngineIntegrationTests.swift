import RawEngine
import XCTest
@testable import Pickroom

final class RawEngineIntegrationTests: XCTestCase {
    func testBundledLibRawVersion() {
        XCTAssertTrue(
            RawDecoder.version.hasPrefix("0.22.2"),
            "Unexpected LibRaw version: \(RawDecoder.version)"
        )
    }

    func testRealRawFixturesWhenProvided() throws {
        let explicitFixtures = ProcessInfo.processInfo.environment["PICKROOM_RAW_FIXTURES"]
        let fixtureURLs: [URL]

        if let explicitFixtures, !explicitFixtures.isEmpty {
            fixtureURLs = explicitFixtures
                .split(separator: ":")
                .map { URL(fileURLWithPath: String($0)) }
        } else {
            let fixtureDirectory = URL(
                fileURLWithPath: "/tmp/pickroom-raw-fixtures",
                isDirectory: true
            )
            fixtureURLs = (try? FileManager.default.contentsOfDirectory(
                at: fixtureDirectory,
                includingPropertiesForKeys: nil
            ))?
            .filter { ["dng", "nef", "arw"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            ?? []
        }

        guard !fixtureURLs.isEmpty else {
            throw XCTSkip("Provide RAW fixtures or populate /tmp/pickroom-raw-fixtures.")
        }

        for url in fixtureURLs {
            let metadata = try RawDecoder.metadata(from: url)
            XCTAssertNotNil(metadata.cameraModel, "Missing camera model for \(url.lastPathComponent)")
            XCTAssertNotNil(metadata.width, "Missing width for \(url.lastPathComponent)")
            XCTAssertNotNil(metadata.height, "Missing height for \(url.lastPathComponent)")

            let fallbackMetadata = MetadataReader.read(
                from: url,
                isRaw: true,
                imageIOProperties: nil
            )
            XCTAssertTrue(
                fallbackMetadata.decoderName.hasPrefix("LibRaw 0.22.2"),
                "Pickroom did not use LibRaw for \(url.lastPathComponent)"
            )
            XCTAssertNotNil(
                fallbackMetadata.cameraModel,
                "Pickroom fallback missed camera model for \(url.lastPathComponent)"
            )
            XCTAssertNotNil(
                fallbackMetadata.pixelWidth,
                "Pickroom fallback missed width for \(url.lastPathComponent)"
            )
            XCTAssertNotNil(
                fallbackMetadata.pixelHeight,
                "Pickroom fallback missed height for \(url.lastPathComponent)"
            )

            if let thumbnail = try? RawDecoder.thumbnail(from: url) {
                let image = try XCTUnwrap(thumbnail.cgImage())
                XCTAssertGreaterThan(image.width, 0)
                XCTAssertGreaterThan(image.height, 0)
            }

            let preview = try RawDecoder.preview(from: url, halfSize: true)
            let renderedImage = try XCTUnwrap(preview.cgImage())
            XCTAssertGreaterThan(renderedImage.width, 0)
            XCTAssertGreaterThan(renderedImage.height, 0)

            let fullPreview = try RawDecoder.preview(from: url, halfSize: false)
            let fullImage = try XCTUnwrap(fullPreview.cgImage())
            XCTAssertGreaterThanOrEqual(fullImage.width, renderedImage.width)
            XCTAssertGreaterThanOrEqual(fullImage.height, renderedImage.height)
        }
    }
}
