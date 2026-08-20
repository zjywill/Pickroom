import AppKit
import CoreGraphics
import Foundation
import Photos
import UniformTypeIdentifiers

typealias PhotoCollectionID = String

struct PhotoCollection: Identifiable, Hashable, Sendable {
    static let allPhotosID: PhotoCollectionID = "pickroom.allPhotos"

    let id: PhotoCollectionID
    let title: String
    let symbol: String
    let count: Int

    var isAllPhotos: Bool {
        id == Self.allPhotosID
    }
}

enum PhotoKitAccess: Sendable {
    case notDetermined
    case denied
    case restricted
    case limited
    case authorized

    var canRead: Bool {
        self == .authorized || self == .limited
    }

    var explanation: String? {
        switch self {
        case .authorized, .limited:
            nil
        case .notDetermined:
            "Pickroom has not asked for photo library access yet."
        case .denied:
            "Pickroom cannot read your photo library. Grant access in "
                + "System Settings → Privacy & Security → Photos."
        case .restricted:
            "Photo library access is restricted on this Mac."
        }
    }
}

/// A preview produced by PhotoKit rather than by decoding a file.
struct PhotoKitImage: @unchecked Sendable {
    let cgImage: CGImage
    /// True when this is the best copy stored on this Mac and the original
    /// still lives in iCloud. Zooming past this resolution needs a download.
    let isLocalStandIn: Bool
}

struct PhotoResourceDetails: Sendable {
    let filename: String
    let isRaw: Bool
    let fileExtension: String
}

enum PhotoKitError: LocalizedError {
    case notAuthorized
    case assetMissing
    case noDownloadableOriginal
    case downloadFailed(String)
    case deleteFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            "Pickroom does not have access to your photo library."
        case .assetMissing:
            "That photo is no longer in the library."
        case .noDownloadableOriginal:
            "That photo has no original file to download."
        case let .downloadFailed(reason):
            reason
        case let .deleteFailed(reason):
            reason
        case .cancelled:
            "The change was cancelled."
        }
    }
}

/// Reads the system photo library through PhotoKit.
///
/// Browsing never touches the network: previews come from the renders Photos
/// already keeps on this Mac. Original bytes are fetched only through
/// ``downloadOriginal(localIdentifier:progress:)``, which the user triggers
/// explicitly for a single photo.
actor PhotoKitLibrary {
    static let shared = PhotoKitLibrary()

    private let imageManager = PHImageManager.default()
    private let resourceManager = PHAssetResourceManager.default()

    nonisolated var access: PhotoKitAccess {
        Self.access(from: PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    func requestAccess() async -> PhotoKitAccess {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard current == .notDetermined else {
            return Self.access(from: current)
        }

        let status = await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
        return Self.access(from: status)
    }

    // MARK: - Collections

    func collections() -> [PhotoCollection] {
        guard access.canRead else { return [] }

        var results: [PhotoCollection] = [
            PhotoCollection(
                id: PhotoCollection.allPhotosID,
                title: "All Photos",
                symbol: "photo.on.rectangle.angled",
                count: PHAsset.fetchAssets(with: .image, options: Self.fetchOptions()).count
            )
        ]

        results.append(contentsOf: smartAlbums())
        results.append(contentsOf: userAlbums())
        return results
    }

    private func smartAlbums() -> [PhotoCollection] {
        let wanted: [(PHAssetCollectionSubtype, String)] = [
            (.smartAlbumFavorites, "heart.fill"),
            (.smartAlbumRecentlyAdded, "clock.fill"),
            (.smartAlbumRAW, "camera.aperture"),
            (.smartAlbumBursts, "square.stack.3d.down.right.fill"),
            (.smartAlbumPanoramas, "pano.fill"),
            (.smartAlbumScreenshots, "camera.viewfinder")
        ]

        return wanted.compactMap { subtype, symbol in
            let fetch = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum,
                subtype: subtype,
                options: nil
            )
            guard let collection = fetch.firstObject else { return nil }
            return photoCollection(for: collection, symbol: symbol)
        }
    }

    private func userAlbums() -> [PhotoCollection] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "localizedTitle", ascending: true)]

        let fetch = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: options
        )

        var results: [PhotoCollection] = []
        for index in 0..<fetch.count {
            let collection = fetch.object(at: index)
            if let album = photoCollection(for: collection, symbol: "rectangle.stack") {
                results.append(album)
            }
        }
        return results
    }

    private nonisolated func photoCollection(
        for collection: PHAssetCollection,
        symbol: String
    ) -> PhotoCollection? {
        let count = PHAsset.fetchAssets(in: collection, options: Self.fetchOptions()).count
        guard count > 0 else { return nil }

        return PhotoCollection(
            id: collection.localIdentifier,
            title: collection.localizedTitle ?? "Untitled Album",
            symbol: symbol,
            count: count
        )
    }

    // MARK: - Assets

    /// Builds the culling list for a collection.
    ///
    /// Deliberately cheap: only the properties PhotoKit keeps in its local
    /// database. Filenames, RAW flags, and capture settings are resolved later,
    /// per photo, so opening a 50,000 photo library stays fast.
    func assets(in collectionID: PhotoCollectionID) -> [PhotoAsset] {
        guard access.canRead else { return [] }

        let fetch: PHFetchResult<PHAsset>
        if collectionID == PhotoCollection.allPhotosID {
            fetch = PHAsset.fetchAssets(with: .image, options: Self.fetchOptions())
        } else {
            let collections = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [collectionID],
                options: nil
            )
            guard let collection = collections.firstObject else { return [] }
            fetch = PHAsset.fetchAssets(in: collection, options: Self.fetchOptions())
        }

        var results: [PhotoAsset] = []
        results.reserveCapacity(fetch.count)

        for index in 0..<fetch.count {
            let asset = fetch.object(at: index)

            var metadata = PhotoMetadata.placeholder(fileExtension: "", isRaw: false)
            metadata.pixelWidth = asset.pixelWidth
            metadata.pixelHeight = asset.pixelHeight
            metadata.capturedAt = asset.creationDate?.formatted(
                date: .abbreviated,
                time: .shortened
            )
            metadata.decoderName = "Photos"
            metadata.requiresOriginalForDetails = true

            results.append(
                PhotoAsset(
                    source: .photoKit(localIdentifier: asset.localIdentifier),
                    filename: Self.provisionalName(for: asset),
                    metadata: metadata
                )
            )
        }

        return results
    }

    /// Resolves the original filename and RAW flag for one photo. Reads the
    /// local resource records only — no network, no download.
    func resourceDetails(localIdentifier: String) -> PhotoResourceDetails? {
        guard let asset = Self.asset(for: localIdentifier) else { return nil }

        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = Self.preferredResource(in: resources) else { return nil }

        let filename = resource.originalFilename
        let fileExtension = (filename as NSString).pathExtension
        return PhotoResourceDetails(
            filename: filename,
            isRaw: Self.isRaw(resource),
            fileExtension: fileExtension
        )
    }

    // MARK: - Previews

    /// Returns the best preview Photos can produce.
    ///
    /// `allowsNetworkAccess` stays false for every browsing path, so an
    /// iCloud-only photo yields its local stand-in instead of downloading.
    func image(
        localIdentifier: String,
        maxPixelSize: Int,
        allowsNetworkAccess: Bool = false
    ) async -> PhotoKitImage? {
        guard let asset = Self.asset(for: localIdentifier) else { return nil }

        let target = CGSize(width: maxPixelSize, height: maxPixelSize)
        if let image = await requestImage(
            asset: asset,
            target: target,
            deliveryMode: .highQualityFormat,
            allowsNetworkAccess: allowsNetworkAccess
        ) {
            return image
        }

        // The high quality render lives in iCloud. Fall back to whatever this
        // Mac already has rather than reaching for the network.
        guard let fallback = await requestImage(
            asset: asset,
            target: target,
            deliveryMode: .fastFormat,
            allowsNetworkAccess: false
        ) else {
            return nil
        }

        return PhotoKitImage(cgImage: fallback.cgImage, isLocalStandIn: true)
    }

    private func requestImage(
        asset: PHAsset,
        target: CGSize,
        deliveryMode: PHImageRequestOptionsDeliveryMode,
        allowsNetworkAccess: Bool
    ) async -> PhotoKitImage? {
        let options = PHImageRequestOptions()
        // Never `.opportunistic`: it calls the result handler more than once.
        options.deliveryMode = deliveryMode
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = allowsNetworkAccess
        options.isSynchronous = false

        let nativeLongEdge = max(asset.pixelWidth, asset.pixelHeight)
        let requestedLongEdge = Int(max(target.width, target.height))

        return await withCheckedContinuation { continuation in
            let box = ResumeBox()
            imageManager.requestImage(
                for: asset,
                targetSize: target,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                guard box.claim() else { return }

                guard let cgImage = image?.pickroomCGImage else {
                    continuation.resume(returning: nil)
                    return
                }

                let degraded = (info?[PHImageResultIsDegradedKey] as? NSNumber)?.boolValue ?? false
                let inCloud = (info?[PHImageResultIsInCloudKey] as? NSNumber)?.boolValue ?? false
                let deliveredLongEdge = max(cgImage.width, cgImage.height)
                let shortOfRequest = deliveredLongEdge < min(requestedLongEdge, nativeLongEdge) * 9 / 10

                continuation.resume(
                    returning: PhotoKitImage(
                        cgImage: cgImage,
                        isLocalStandIn: degraded || inCloud || shortOfRequest
                    )
                )
            }
        }
    }

    // MARK: - Explicit original download

    /// Writes one photo's original bytes into Pickroom's cache. This is the
    /// only path that is allowed to hit the network, and only the user can
    /// start it.
    func downloadOriginal(
        localIdentifier: String,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        guard access.canRead else { throw PhotoKitError.notAuthorized }
        guard let asset = Self.asset(for: localIdentifier) else {
            throw PhotoKitError.assetMissing
        }

        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = Self.preferredResource(in: resources) else {
            throw PhotoKitError.noDownloadableOriginal
        }

        let destination = try Self.originalsDirectory(for: localIdentifier)
            .appendingPathComponent(resource.originalFilename)

        if FileManager.default.fileExists(atPath: destination.path) {
            progress?(1)
            return destination
        }

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        if let progress {
            options.progressHandler = { value in progress(value) }
        }

        do {
            try await resourceManager.writeData(
                for: resource,
                toFile: destination,
                options: options
            )
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw PhotoKitError.downloadFailed(error.localizedDescription)
        }

        progress?(1)
        return destination
    }

    /// Removes a previously downloaded original. Photos keeps the real copy.
    nonisolated func discardDownloadedOriginal(at url: URL) {
        let container = url.deletingLastPathComponent()
        guard container.path.hasPrefix(Self.originalsRoot.path) else { return }
        try? FileManager.default.removeItem(at: container)
    }

    // MARK: - Deletion

    /// Moves photos to Recently Deleted. macOS shows its own confirmation
    /// sheet before anything is removed, and the photos stay recoverable there.
    func delete(localIdentifiers: [String]) async throws {
        guard !localIdentifiers.isEmpty else { return }
        guard access.canRead else { throw PhotoKitError.notAuthorized }

        let assets = PHAsset.fetchAssets(
            withLocalIdentifiers: localIdentifiers,
            options: nil
        )
        guard assets.count > 0 else { return }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
        } catch {
            if Self.isUserCancellation(error) {
                throw PhotoKitError.cancelled
            }
            throw PhotoKitError.deleteFailed(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private static func fetchOptions() -> PHFetchOptions {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "mediaType == %d",
            PHAssetMediaType.image.rawValue
        )
        options.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: true)
        ]
        options.includeHiddenAssets = false
        return options
    }

    /// `PHPhotosErrorUserCancelled` and `NSUserCancelledError` share this code.
    private static func isUserCancellation(_ error: Error) -> Bool {
        (error as NSError).code == 3072
    }

    private static func asset(for localIdentifier: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject
    }

    /// Mirrors the folder scanner's RAW-first pairing: when a shot exists as
    /// RAW + JPEG, PhotoKit stores the RAW as the alternate resource.
    private static func preferredResource(in resources: [PHAssetResource]) -> PHAssetResource? {
        let originals = resources.filter {
            $0.type == .photo || $0.type == .alternatePhoto
        }
        if let raw = originals.first(where: isRaw) {
            return raw
        }
        return originals.first(where: { $0.type == .photo }) ?? originals.first
    }

    private static func isRaw(_ resource: PHAssetResource) -> Bool {
        if let type = UTType(resource.uniformTypeIdentifier), type.conforms(to: .rawImage) {
            return true
        }
        let ext = (resource.originalFilename as NSString).pathExtension.lowercased()
        return PhotoLibraryScanner.rawExtensions.contains(ext)
    }

    private static func provisionalName(for asset: PHAsset) -> String {
        guard let date = asset.creationDate else { return "Photo" }
        return date.formatted(date: .numeric, time: .standard)
    }

    private static var originalsRoot: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches
            .appendingPathComponent("Pickroom", isDirectory: true)
            .appendingPathComponent("Originals", isDirectory: true)
    }

    private static func originalsDirectory(for localIdentifier: String) throws -> URL {
        let slug = localIdentifier
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let directory = originalsRoot.appendingPathComponent(slug, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private static func access(from status: PHAuthorizationStatus) -> PhotoKitAccess {
        switch status {
        case .authorized: .authorized
        case .limited: .limited
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }
}

/// PhotoKit result handlers can fire more than once for some delivery modes.
/// This guarantees a checked continuation is resumed exactly once.
private final class ResumeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}

private extension NSImage {
    /// PhotoKit hands back an `NSImage` on macOS. Ask for the representation's
    /// real pixel dimensions rather than its point size, otherwise a Retina
    /// render comes back at half resolution and looks like a cloud stand-in.
    var pickroomCGImage: CGImage? {
        if let representation = representations.first,
           representation.pixelsWide > 0,
           representation.pixelsHigh > 0 {
            var rect = CGRect(
                x: 0,
                y: 0,
                width: CGFloat(representation.pixelsWide),
                height: CGFloat(representation.pixelsHigh)
            )
            if let image = cgImage(forProposedRect: &rect, context: nil, hints: nil) {
                return image
            }
        }

        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
