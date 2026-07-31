import Foundation
import XCTest
@testable import Pickroom

final class RejectedPhotoManagerTests: XCTestCase {
    private var temporaryFolder: URL!

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

    func testCollectsStandaloneRejectIntoHiddenFolder() async throws {
        let sourceURL = temporaryFolder.appendingPathComponent("session/photo.dng")
        try createFile(at: sourceURL)
        let asset = makeAsset(url: sourceURL)
        let manager = RejectedPhotoManager()

        let result = await manager.collect([asset], in: temporaryFolder)

        let relocation = try XCTUnwrap(result.relocations.first)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: relocation.destinationURL.path))
        XCTAssertEqual(
            relocation.destinationURL.path,
            RejectArchive.folder(in: temporaryFolder)
                .appendingPathComponent("session/photo.dng")
                .path
        )
    }

    func testCollectsPairedRawAndJPEGTogether() async throws {
        let rawURL = temporaryFolder.appendingPathComponent("session/DSC0001.arw")
        let jpegURL = temporaryFolder.appendingPathComponent("session/DSC0001.jpg")
        try createFile(at: rawURL)
        try createFile(at: jpegURL)
        let asset = makeAsset(url: rawURL, companionURL: jpegURL)
        let manager = RejectedPhotoManager()

        let result = await manager.collect([asset], in: temporaryFolder)

        let relocation = try XCTUnwrap(result.relocations.first)
        let archivedJPEG = try XCTUnwrap(relocation.destinationCompanionURL)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: relocation.destinationURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: archivedJPEG.path))
        XCTAssertEqual(
            relocation.destinationURL.deletingPathExtension().lastPathComponent,
            archivedJPEG.deletingPathExtension().lastPathComponent
        )
    }

    func testCollectUsesSharedCollisionSuffixForPair() async throws {
        let rawURL = temporaryFolder.appendingPathComponent("DSC0002.nef")
        let jpegURL = temporaryFolder.appendingPathComponent("DSC0002.jpg")
        try createFile(at: rawURL)
        try createFile(at: jpegURL)

        let archive = RejectArchive.folder(in: temporaryFolder)
        try createFile(at: archive.appendingPathComponent("DSC0002.nef"))
        try createFile(at: archive.appendingPathComponent("DSC0002.jpg"))

        let manager = RejectedPhotoManager()
        let result = await manager.collect(
            [makeAsset(url: rawURL, companionURL: jpegURL)],
            in: temporaryFolder
        )

        let relocation = try XCTUnwrap(result.relocations.first)
        let archivedJPEG = try XCTUnwrap(relocation.destinationCompanionURL)
        XCTAssertEqual(relocation.destinationURL.lastPathComponent, "DSC0002 (1).nef")
        XCTAssertEqual(archivedJPEG.lastPathComponent, "DSC0002 (1).jpg")
    }

    func testRestoresCollectedPairToSourceFolder() async throws {
        let rawURL = temporaryFolder.appendingPathComponent("nested/DSC0003.cr3")
        let jpegURL = temporaryFolder.appendingPathComponent("nested/DSC0003.jpg")
        try createFile(at: rawURL)
        try createFile(at: jpegURL)

        let manager = RejectedPhotoManager()
        let asset = makeAsset(url: rawURL, companionURL: jpegURL)
        let collected = await manager.collect([asset], in: temporaryFolder)
        let collectedMove = try XCTUnwrap(collected.relocations.first)
        let archivedAsset = makeAsset(
            id: asset.id,
            url: collectedMove.destinationURL,
            companionURL: collectedMove.destinationCompanionURL,
            isArchived: true
        )

        let restored = await manager.restore([archivedAsset], to: temporaryFolder)

        let restoredMove = try XCTUnwrap(restored.relocations.first)
        XCTAssertTrue(restored.failures.isEmpty)
        XCTAssertEqual(restoredMove.destinationURL.path, rawURL.path)
        XCTAssertEqual(restoredMove.destinationCompanionURL?.path, jpegURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: rawURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: jpegURL.path))
    }

    func testCollectRollsBackPrimaryWhenCompanionMoveFails() async throws {
        let rawURL = temporaryFolder.appendingPathComponent("DSC0006.arw")
        let missingJPEG = temporaryFolder.appendingPathComponent("DSC0006.jpg")
        try createFile(at: rawURL)

        let manager = RejectedPhotoManager()
        let result = await manager.collect(
            [makeAsset(url: rawURL, companionURL: missingJPEG)],
            in: temporaryFolder
        )

        XCTAssertTrue(result.relocations.isEmpty)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: rawURL.path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: RejectArchive.folder(in: temporaryFolder)
                    .appendingPathComponent("DSC0006.arw")
                    .path
            )
        )
    }

    func testScannerIncludesRejectArchiveButSkipsOtherHiddenFolders() async throws {
        let visibleURL = temporaryFolder.appendingPathComponent("visible.jpg")
        let archivedURL = RejectArchive.folder(in: temporaryFolder)
            .appendingPathComponent("archived.dng")
        let unrelatedHiddenURL = temporaryFolder.appendingPathComponent(".private/hidden.jpg")
        try createFile(at: visibleURL)
        try createFile(at: archivedURL)
        try createFile(at: unrelatedHiddenURL)

        let assets = await PhotoLibraryScanner().scan(folder: temporaryFolder)

        XCTAssertEqual(assets.count, 2)
        XCTAssertEqual(assets.count(where: \.isArchived), 1)
        XCTAssertEqual(assets.first(where: \.isArchived)?.decision, .reject)
        XCTAssertFalse(assets.contains { $0.url.lastPathComponent == "hidden.jpg" })
    }

    func testSelectionMigrationMovesDecisionAndRatingToNewPath() {
        let oldKey = "/photos/DSC0004.arw"
        let newKey = "/photos/.pickroom-rejects/DSC0004.arw"
        let selection = StoredSelection(decision: .reject, rating: 4)

        let migrated = StoredSelectionKeyMigration.applying(
            [
                StoredSelectionKeyMove(
                    sourceKey: oldKey,
                    destinationKey: newKey,
                    selection: selection
                )
            ],
            to: [oldKey: selection]
        )

        XCTAssertNil(migrated[oldKey])
        XCTAssertEqual(migrated[newKey], selection)
    }

    @MainActor
    func testReclassifyingCollectedRejectAutomaticallyRestoresAndRefreshesCounts() async throws {
        let sourceURL = temporaryFolder.appendingPathComponent("DSC0007.jpg")
        try createFile(at: sourceURL)
        let manager = RejectedPhotoManager()
        let collected = await manager.collect(
            [makeAsset(url: sourceURL)],
            in: temporaryFolder
        )
        XCTAssertEqual(collected.relocations.count, 1)

        let selectionStore = SelectionStore(
            fileURL: temporaryFolder.appendingPathComponent("state/selections.json")
        )
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: "PickroomTests.\(UUID().uuidString)")
        )
        let model = AppModel(
            scanner: PhotoLibraryScanner(),
            selectionStore: selectionStore,
            rejectedPhotoManager: manager,
            userDefaults: defaults
        )

        await model.loadFolder(temporaryFolder)

        XCTAssertEqual(model.archivedAssetCount, 1)
        XCTAssertEqual(model.count(for: .rejects), 1)

        model.setDecision(.pick, advance: false)
        for _ in 0..<100 where model.archivedAssetCount > 0 {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(model.archivedAssetCount, 0)
        XCTAssertEqual(model.count(for: .rejects), 0)
        XCTAssertEqual(model.count(for: .picks), 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    @MainActor
    func testAppModelMovesCurrentRejectsDirectlyToInjectedTrash() async throws {
        let sourceURL = temporaryFolder.appendingPathComponent("DSC0008.jpg")
        try createFile(at: sourceURL)
        let fakeTrashFolder = temporaryFolder.appendingPathComponent(
            ".test-app-trash",
            isDirectory: true
        )
        let trashMover = RecordingTrashMover(destinationFolder: fakeTrashFolder)
        let selectionStore = SelectionStore(
            fileURL: temporaryFolder.appendingPathComponent("state/selections.json")
        )
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: "PickroomTests.\(UUID().uuidString)")
        )
        let model = AppModel(
            scanner: PhotoLibraryScanner(),
            selectionStore: selectionStore,
            rejectedPhotoManager: RejectedPhotoManager(trashMover: trashMover),
            userDefaults: defaults
        )

        await model.loadFolder(temporaryFolder)
        model.setDecision(.reject, advance: false)

        XCTAssertEqual(model.rejectedAssetCount, 1)
        model.requestTrashConfirmation()
        XCTAssertTrue(model.isShowingTrashConfirmation)

        await model.moveRejectedPhotosToTrash()

        XCTAssertEqual(model.rejectedAssetCount, 0)
        XCTAssertTrue(model.assets.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: fakeTrashFolder.appendingPathComponent("DSC0008.jpg").path
            )
        )
    }

    func testTrashUsesInjectedMoverForArchivedPair() async throws {
        let rawURL = temporaryFolder.appendingPathComponent(
            "\(RejectArchive.directoryName)/DSC0005.raw"
        )
        let jpegURL = temporaryFolder.appendingPathComponent(
            "\(RejectArchive.directoryName)/DSC0005.jpg"
        )
        try createFile(at: rawURL)
        try createFile(at: jpegURL)

        let fakeTrashFolder = temporaryFolder.appendingPathComponent(
            ".test-trash",
            isDirectory: true
        )
        let trashMover = RecordingTrashMover(destinationFolder: fakeTrashFolder)
        let manager = RejectedPhotoManager(trashMover: trashMover)
        let asset = makeAsset(
            url: rawURL,
            companionURL: jpegURL,
            isArchived: true
        )

        let result = await manager.moveToTrash([asset])
        let movedURLs = await trashMover.movedURLs

        XCTAssertEqual(result.completedAssetIDs, [asset.id])
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(Set(movedURLs.map(\.lastPathComponent)), ["DSC0005.raw", "DSC0005.jpg"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: rawURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: jpegURL.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: fakeTrashFolder.appendingPathComponent("DSC0005.raw").path
            )
        )
    }

    private func makeAsset(
        id: UUID = UUID(),
        url: URL,
        companionURL: URL? = nil,
        isArchived: Bool = false
    ) -> PhotoAsset {
        PhotoAsset(
            id: id,
            url: url,
            companionURL: companionURL,
            decision: .reject,
            rating: 3,
            metadata: .placeholder(
                for: url,
                isRaw: PhotoLibraryScanner.isRaw(url)
            ),
            isArchived: isArchived
        )
    }

    private func createFile(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("fixture".utf8).write(to: url)
    }
}

private actor RecordingTrashMover: TrashMoving {
    private(set) var movedURLs: [URL] = []
    private let destinationFolder: URL

    init(destinationFolder: URL) {
        self.destinationFolder = destinationFolder
    }

    func moveToTrash(_ urls: [URL]) async throws {
        try FileManager.default.createDirectory(
            at: destinationFolder,
            withIntermediateDirectories: true
        )

        for url in urls {
            let destination = destinationFolder.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            movedURLs.append(url)
        }
    }
}
