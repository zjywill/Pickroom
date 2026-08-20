import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Pickroom

final class PhotoLocationTests: XCTestCase {
    private var temporaryFolder: URL!

    private let beijing = PhotoLocation(latitude: 39.9042, longitude: 116.4074)!
    private let sydney = PhotoLocation(latitude: -33.8688, longitude: 151.2093)!

    override func setUpWithError() throws {
        temporaryFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PickroomTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryFolder,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryFolder {
            try? FileManager.default.removeItem(at: temporaryFolder)
        }
    }

    // MARK: - Coordinate formatting

    func testFormatsCoordinatesAsDegreesAndDecimalMinutes() {
        XCTAssertEqual(GPSCoordinateFormat.xmp(39.9042, isLatitude: true), "39,54.2520N")
        XCTAssertEqual(GPSCoordinateFormat.xmp(116.4074, isLatitude: false), "116,24.4440E")
    }

    func testFormatsSouthernAndWesternHemispheres() {
        XCTAssertEqual(GPSCoordinateFormat.xmp(-33.8688, isLatitude: true), "33,52.1280S")
        XCTAssertEqual(GPSCoordinateFormat.xmp(-70.6693, isLatitude: false), "70,40.1580W")
    }

    func testParsesBothDecimalMinuteAndSecondSpellings() throws {
        let decimalMinutes = try XCTUnwrap(GPSCoordinateFormat.value(fromXMP: "39,54.2520N"))
        XCTAssertEqual(decimalMinutes, 39.9042, accuracy: 0.0001)

        let seconds = try XCTUnwrap(GPSCoordinateFormat.value(fromXMP: "39,54,15N"))
        XCTAssertEqual(seconds, 39.904166, accuracy: 0.0001)

        let southern = try XCTUnwrap(GPSCoordinateFormat.value(fromXMP: "33,52.1280S"))
        XCTAssertEqual(southern, -33.8688, accuracy: 0.0001)
    }

    func testRejectsCoordinatesWithoutAHemisphere() {
        XCTAssertNil(GPSCoordinateFormat.value(fromXMP: "39,54.2520"))
        XCTAssertNil(GPSCoordinateFormat.value(fromXMP: ""))
        XCTAssertNil(GPSCoordinateFormat.value(fromXMP: "nonsense"))
    }

    func testRejectsOutOfRangeCoordinates() {
        XCTAssertNil(PhotoLocation(latitude: 91, longitude: 0))
        XCTAssertNil(PhotoLocation(latitude: 0, longitude: 181))
        XCTAssertNil(PhotoLocation(latitude: .nan, longitude: 0))
    }

    // MARK: - Format routing

    func testRoutesProprietaryRawToASidecar() throws {
        let raw = temporaryFolder.appendingPathComponent("DSC0001.ARW")
        XCTAssertEqual(
            try PhotoLocationWriter.target(for: raw),
            .sidecar(temporaryFolder.appendingPathComponent("DSC0001.xmp"))
        )
    }

    /// DNG is raw but Adobe treats it as writable and ignores a sidecar next
    /// to one, so it has to go in the file.
    func testRoutesDNGInPlaceRatherThanToASidecar() throws {
        let dng = temporaryFolder.appendingPathComponent("DSC0001.DNG")
        XCTAssertEqual(try PhotoLocationWriter.target(for: dng), .inPlace(dng))
    }

    func testRoutesJPEGInPlace() throws {
        let jpeg = temporaryFolder.appendingPathComponent("DSC0001.jpg")
        XCTAssertEqual(try PhotoLocationWriter.target(for: jpeg), .inPlace(jpeg))
    }

    func testRefusesFormatsWithNowhereToPutCoordinates() {
        let svg = temporaryFolder.appendingPathComponent("logo.svg")
        XCTAssertThrowsError(try PhotoLocationWriter.target(for: svg)) { error in
            XCTAssertEqual(error as? LocationWriteError, .unsupportedFormat("SVG"))
        }
    }

    // MARK: - Sidecar

    func testWritesAndReadsBackASidecar() throws {
        let raw = temporaryFolder.appendingPathComponent("DSC0002.ARW")
        try Data("raw bytes".utf8).write(to: raw)

        try PhotoLocationWriter.write(beijing, to: raw)

        let read = try XCTUnwrap(PhotoLocationWriter.read(from: raw))
        XCTAssertEqual(read.latitude, beijing.latitude, accuracy: 0.0001)
        XCTAssertEqual(read.longitude, beijing.longitude, accuracy: 0.0001)
    }

    func testSidecarLeavesTheRawFileUntouched() throws {
        let raw = temporaryFolder.appendingPathComponent("DSC0003.CR3")
        let original = Data("pretend this is a canon raw".utf8)
        try original.write(to: raw)

        try PhotoLocationWriter.write(sydney, to: raw)

        XCTAssertEqual(try Data(contentsOf: raw), original)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: temporaryFolder.appendingPathComponent("DSC0003.xmp").path
            )
        )
    }

    /// The sidecar may already hold develop settings or keywords from another
    /// tool. Storing two numbers must not cost the user that work.
    func testKeepsExistingSidecarContentWhenAddingCoordinates() throws {
        let raw = temporaryFolder.appendingPathComponent("DSC0004.NEF")
        try Data("raw".utf8).write(to: raw)

        let sidecar = temporaryFolder.appendingPathComponent("DSC0004.xmp")
        try Data("""
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description rdf:about="" xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
              crs:Exposure2012="+1.35" crs:Temperature="5500"/>
          </rdf:RDF>
        </x:xmpmeta>
        """.utf8).write(to: sidecar)

        try PhotoLocationWriter.write(beijing, to: raw)

        let updated = try String(contentsOf: sidecar, encoding: .utf8)
        XCTAssertTrue(updated.contains("crs:Exposure2012=\"+1.35\""))
        XCTAssertTrue(updated.contains("crs:Temperature=\"5500\""))
        XCTAssertTrue(updated.contains("exif:GPSLatitude"))
        XCTAssertNotNil(PhotoLocationWriter.read(from: raw))
    }

    func testOverwritingASidecarReplacesRatherThanDuplicatesCoordinates() throws {
        let raw = temporaryFolder.appendingPathComponent("DSC0005.ARW")
        try Data("raw".utf8).write(to: raw)

        try PhotoLocationWriter.write(beijing, to: raw)
        try PhotoLocationWriter.write(sydney, to: raw)

        let read = try XCTUnwrap(PhotoLocationWriter.read(from: raw))
        XCTAssertEqual(read.latitude, sydney.latitude, accuracy: 0.0001)
        XCTAssertEqual(read.longitude, sydney.longitude, accuracy: 0.0001)

        let sidecar = try String(
            contentsOf: temporaryFolder.appendingPathComponent("DSC0005.xmp"),
            encoding: .utf8
        )
        XCTAssertEqual(sidecar.components(separatedBy: "exif:GPSLatitude").count - 1, 1)
    }

    // MARK: - In place

    func testWritesCoordinatesIntoAJPEGAndReadsThemBack() throws {
        let jpeg = try makeJPEG(named: "DSC0006.jpg")

        XCTAssertNil(PhotoLocationWriter.read(from: jpeg))
        try PhotoLocationWriter.write(sydney, to: jpeg)

        let read = try XCTUnwrap(PhotoLocationWriter.read(from: jpeg))
        XCTAssertEqual(read.latitude, sydney.latitude, accuracy: 0.0001)
        XCTAssertEqual(read.longitude, sydney.longitude, accuracy: 0.0001)
    }

    /// Tagging a photo must not cost it a JPEG generation, or culling a shoot
    /// twice would visibly degrade it.
    func testInPlaceWriteLeavesThePixelsAlone() throws {
        let jpeg = try makeJPEG(named: "DSC0007.jpg")
        let before = try pixelData(of: jpeg)

        try PhotoLocationWriter.write(beijing, to: jpeg)
        try PhotoLocationWriter.write(sydney, to: jpeg)

        XCTAssertEqual(try pixelData(of: jpeg), before)
    }

    func testInPlaceWriteLeavesTheRestOfTheMetadataAlone() throws {
        let jpeg = try makeJPEG(named: "DSC0008.jpg")
        try PhotoLocationWriter.write(beijing, to: jpeg)

        let metadata = MetadataReader.read(from: jpeg, isRaw: false)
        XCTAssertEqual(metadata.pixelWidth, 8)
        XCTAssertEqual(metadata.pixelHeight, 6)
        XCTAssertNotNil(metadata.location)
    }

    func testMetadataReaderSurfacesASidecarLocationForRaw() throws {
        let raw = temporaryFolder.appendingPathComponent("DSC0009.ARW")
        try Data("raw".utf8).write(to: raw)
        try PhotoLocationWriter.write(beijing, to: raw)

        let metadata = MetadataReader.read(from: raw, isRaw: true)
        let location = try XCTUnwrap(metadata.location)
        XCTAssertEqual(location.latitude, beijing.latitude, accuracy: 0.0001)
    }

    // MARK: - Batch

    func testTaggerAppliesOneLocationToEveryPhotoAndReportsWhatItCannot() async throws {
        let jpeg = try makeJPEG(named: "DSC0010.jpg")
        let raw = temporaryFolder.appendingPathComponent("DSC0011.ARW")
        try Data("raw".utf8).write(to: raw)
        let svg = temporaryFolder.appendingPathComponent("logo.svg")
        try Data("<svg/>".utf8).write(to: svg)

        let assets = [jpeg, raw, svg].map { url in
            PhotoAsset(
                url: url,
                metadata: .placeholder(for: url, isRaw: PhotoLibraryScanner.isRaw(url))
            )
        }

        let result = await LocationTagger().apply(beijing, to: assets)

        XCTAssertEqual(result.taggedAssetIDs.count, 2)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(result.failures.first?.filename, "logo.svg")
        XCTAssertNotNil(PhotoLocationWriter.read(from: jpeg))
        XCTAssertNotNil(PhotoLocationWriter.read(from: raw))
    }

    func testTaggerAlsoTagsThePairedJPEGBesideARaw() async throws {
        let raw = temporaryFolder.appendingPathComponent("DSC0012.ARW")
        try Data("raw".utf8).write(to: raw)
        let companion = try makeJPEG(named: "DSC0012.jpg")

        let asset = PhotoAsset(
            url: raw,
            companionURL: companion,
            metadata: .placeholder(for: raw, isRaw: true)
        )

        let result = await LocationTagger().apply(sydney, to: [asset])

        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertNotNil(PhotoLocationWriter.read(from: raw))
        let companionLocation = try XCTUnwrap(PhotoLocationWriter.read(from: companion))
        XCTAssertEqual(companionLocation.latitude, sydney.latitude, accuracy: 0.0001)
    }

    // MARK: - Fixtures

    private func makeJPEG(named name: String) throws -> URL {
        let url = temporaryFolder.appendingPathComponent(name)
        let width = 8
        let height = 6
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        )
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private func pixelData(of url: URL) throws -> Data {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let provider = try XCTUnwrap(image.dataProvider)
        return try XCTUnwrap(provider.data) as Data
    }
}
