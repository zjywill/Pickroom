import XCTest
@testable import Pickroom

final class AssetSourceTests: XCTestCase {
    func testFileSourceKeysOnStandardizedPath() {
        let source = AssetSource.file(URL(fileURLWithPath: "/photos/./sub/../DSC0001.arw"))

        XCTAssertEqual(source.storageKey, "/photos/DSC0001.arw")
        XCTAssertEqual(source.fileURL?.lastPathComponent, "DSC0001.arw")
        XCTAssertNil(source.localIdentifier)
        XCTAssertFalse(source.isPhotoKit)
    }

    func testPhotoKitSourceKeyIsNamespaced() {
        let source = AssetSource.photoKit(localIdentifier: "ABC-123/L0/001")

        XCTAssertEqual(source.storageKey, "photos:ABC-123/L0/001")
        XCTAssertEqual(source.localIdentifier, "ABC-123/L0/001")
        XCTAssertNil(source.fileURL)
        XCTAssertTrue(source.isPhotoKit)
    }

    /// A file path and a Photos identifier must never collide in
    /// `selections.json`, otherwise decisions leak between sources.
    func testFileAndPhotoKitKeysNeverCollide() {
        let file = AssetSource.file(URL(fileURLWithPath: "/photos:ABC"))
        let photos = AssetSource.photoKit(localIdentifier: "ABC")

        XCTAssertNotEqual(file.storageKey, photos.storageKey)
    }

    func testFileAssetNeverNeedsDownload() {
        let asset = PhotoAsset(
            url: URL(fileURLWithPath: "/photos/DSC0002.jpg"),
            metadata: .placeholder(fileExtension: "JPG", isRaw: false)
        )

        XCTAssertFalse(asset.needsOriginalDownload)
        XCTAssertEqual(asset.filename, "DSC0002.jpg")
        XCTAssertEqual(asset.readableFileURL?.path, "/photos/DSC0002.jpg")
        XCTAssertEqual(asset.previewSource, asset.source)
    }

    func testPhotoKitAssetNeedsDownloadUntilOriginalArrives() {
        var asset = PhotoAsset(
            source: .photoKit(localIdentifier: "ABC-123"),
            filename: "IMG_0001.HEIC",
            metadata: .placeholder(fileExtension: "HEIC", isRaw: false)
        )

        XCTAssertTrue(asset.needsOriginalDownload)
        XCTAssertNil(asset.readableFileURL)
        XCTAssertEqual(asset.previewSource, .photoKit(localIdentifier: "ABC-123"))

        let downloaded = URL(fileURLWithPath: "/cache/ABC-123/IMG_0001.HEIC")
        asset.downloadedOriginalURL = downloaded

        XCTAssertFalse(asset.needsOriginalDownload)
        XCTAssertEqual(asset.readableFileURL, downloaded)
        XCTAssertEqual(asset.previewSource, .file(downloaded))
    }

    /// Downloading changes how the photo decodes, so the preview cache must
    /// look it up under a different key than the PhotoKit render.
    func testDownloadedOriginalGetsItsOwnPreviewKey() {
        var asset = PhotoAsset(
            source: .photoKit(localIdentifier: "ABC-123"),
            metadata: .placeholder(fileExtension: "", isRaw: false)
        )
        let beforeKey = asset.previewSource.storageKey
        asset.downloadedOriginalURL = URL(fileURLWithPath: "/cache/ABC-123/IMG_0001.ARW")

        XCTAssertNotEqual(beforeKey, asset.previewSource.storageKey)
        // The persisted decision key must not move with the download.
        XCTAssertEqual(asset.selectionKey, "photos:ABC-123")
    }

    func testLibrarySourceAccessors() {
        let folder = LibrarySource.folder(URL(fileURLWithPath: "/photos/shoot"))
        XCTAssertEqual(folder.folderURL?.lastPathComponent, "shoot")
        XCTAssertNil(folder.collectionID)
        XCTAssertFalse(folder.isPhotos)

        let photos = LibrarySource.photos(PhotoCollection.allPhotosID)
        XCTAssertEqual(photos.collectionID, PhotoCollection.allPhotosID)
        XCTAssertNil(photos.folderURL)
        XCTAssertTrue(photos.isPhotos)

        XCTAssertNil(LibrarySource.none.folderURL)
        XCTAssertNil(LibrarySource.none.collectionID)
    }
}
