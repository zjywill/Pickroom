import XCTest
@testable import Pickroom

final class CullingShortcutTests: XCTestCase {
    func testMapsDecisionKeys() {
        XCTAssertEqual(CullingShortcut.command(key: "p"), .decision(.pick))
        XCTAssertEqual(CullingShortcut.command(key: "m"), .decision(.maybe))
        XCTAssertEqual(CullingShortcut.command(key: "x"), .decision(.reject))
        XCTAssertEqual(CullingShortcut.command(key: "u"), .unmark)
    }

    func testMapsZoomAndGridKeys() {
        XCTAssertEqual(CullingShortcut.command(key: " "), .toggleActualSize)
        XCTAssertEqual(CullingShortcut.command(key: "z"), .actualSize)
        XCTAssertEqual(CullingShortcut.command(key: "c"), .toggleCompositionGrid)
    }

    func testIgnoresDigitKeys() {
        XCTAssertNil(CullingShortcut.command(key: "0"))
        XCTAssertNil(CullingShortcut.command(key: "5"))
    }

    func testIgnoresModifiedKeys() {
        XCTAssertNil(CullingShortcut.command(key: "p", modifiers: .command))
        XCTAssertNil(CullingShortcut.command(key: "0", modifiers: .command))
        XCTAssertNil(CullingShortcut.command(key: " ", modifiers: .option))
    }

    func testIgnoresUnusedKeys() {
        XCTAssertNil(CullingShortcut.command(key: "q"))
        XCTAssertNil(CullingShortcut.command(key: "\r"))
    }

    @MainActor
    func testToggleActualSizeSwitchesBetweenFitAndActualSize() {
        let model = AppModel()
        model.assets = [
            PhotoAsset(
                url: URL(fileURLWithPath: "/tmp/DSC0001.ARW"),
                companionURL: nil,
                metadata: .placeholder(
                    for: URL(fileURLWithPath: "/tmp/DSC0001.ARW"),
                    isRaw: true
                )
            )
        ]
        model.currentAssetID = model.assets.first?.id
        model.updateFitPixelScale(0.25)

        model.toggleActualSize()
        XCTAssertEqual(model.zoomScale, 4, accuracy: 0.001)

        model.toggleActualSize()
        XCTAssertEqual(model.zoomScale, 1, accuracy: 0.001)
    }

    @MainActor
    func testToggleActualSizeIgnoredWithoutSelection() {
        let model = AppModel()
        model.updateFitPixelScale(0.25)

        model.toggleActualSize()

        XCTAssertEqual(model.zoomScale, 1, accuracy: 0.001)
    }
}
