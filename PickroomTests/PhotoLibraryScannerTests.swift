import XCTest
@testable import Pickroom

final class PhotoLibraryScannerTests: XCTestCase {
    func testRecognizesCommonRawExtensions() {
        XCTAssertTrue(PhotoLibraryScanner.isRaw(URL(fileURLWithPath: "/tmp/a.CR3")))
        XCTAssertTrue(PhotoLibraryScanner.isRaw(URL(fileURLWithPath: "/tmp/a.ARW")))
        XCTAssertTrue(PhotoLibraryScanner.isRaw(URL(fileURLWithPath: "/tmp/a.DNG")))
    }

    func testPairsRawAndJPEGUsingRawAsPrimary() {
        let raw = URL(fileURLWithPath: "/tmp/DSC0001.ARW")
        let jpeg = URL(fileURLWithPath: "/tmp/DSC0001.JPG")

        let result = PhotoLibraryScanner.preferredPhotoPairs(from: [jpeg, raw])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.0, raw)
        XCTAssertEqual(result.first?.1, jpeg)
    }

    func testLeavesStandaloneJPEGVisible() {
        let jpeg = URL(fileURLWithPath: "/tmp/DSC0002.JPG")

        let result = PhotoLibraryScanner.preferredPhotoPairs(from: [jpeg])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.0, jpeg)
        XCTAssertNil(result.first?.1)
    }
}
