import Foundation

/// Where a photo lives.
///
/// Folder culling keeps working on file URLs. Photos library assets are
/// identified by their PhotoKit local identifier and only materialize as a
/// file once the user explicitly downloads the original.
enum AssetSource: Hashable, Sendable {
    case file(URL)
    case photoKit(localIdentifier: String)

    var fileURL: URL? {
        guard case let .file(url) = self else { return nil }
        return url
    }

    var localIdentifier: String? {
        guard case let .photoKit(identifier) = self else { return nil }
        return identifier
    }

    var isPhotoKit: Bool {
        localIdentifier != nil
    }

    /// Stable key for persisted decisions and preview cache entries.
    var storageKey: String {
        switch self {
        case let .file(url): url.standardizedFileURL.path
        case let .photoKit(identifier): "photos:\(identifier)"
        }
    }
}

/// What the workspace is currently culling.
enum LibrarySource: Hashable, Sendable {
    case none
    case folder(URL)
    case photos(PhotoCollectionID)

    var folderURL: URL? {
        guard case let .folder(url) = self else { return nil }
        return url
    }

    var collectionID: PhotoCollectionID? {
        guard case let .photos(id) = self else { return nil }
        return id
    }

    var isPhotos: Bool {
        collectionID != nil
    }
}
