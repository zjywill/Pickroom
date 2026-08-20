import Foundation

struct PhotoAsset: Identifiable, Hashable, Sendable {
    let id: UUID
    var source: AssetSource
    var filename: String
    var companionURL: URL?
    var decision: PhotoDecision
    var metadata: PhotoMetadata
    var isArchived: Bool
    /// Set once the user downloads a Photos original; the file pipeline then
    /// takes over for full resolution, RAW decoding, and EXIF.
    var downloadedOriginalURL: URL?

    init(
        id: UUID = UUID(),
        source: AssetSource,
        filename: String? = nil,
        companionURL: URL? = nil,
        decision: PhotoDecision = .unreviewed,
        metadata: PhotoMetadata,
        isArchived: Bool = false,
        downloadedOriginalURL: URL? = nil
    ) {
        self.id = id
        self.source = source
        self.filename = filename
            ?? source.fileURL?.lastPathComponent
            ?? source.storageKey
        self.companionURL = companionURL
        self.decision = decision
        self.metadata = metadata
        self.isArchived = isArchived
        self.downloadedOriginalURL = downloadedOriginalURL
    }

    init(
        id: UUID = UUID(),
        url: URL,
        companionURL: URL? = nil,
        decision: PhotoDecision = .unreviewed,
        metadata: PhotoMetadata,
        isArchived: Bool = false
    ) {
        self.init(
            id: id,
            source: .file(url),
            filename: url.lastPathComponent,
            companionURL: companionURL,
            decision: decision,
            metadata: metadata,
            isArchived: isArchived
        )
    }

    var fileURL: URL? {
        source.fileURL
    }

    var isPhotoKitAsset: Bool {
        source.isPhotoKit
    }

    /// The on-disk file backing this asset, if there is one. Photos assets only
    /// have one after an explicit download.
    var readableFileURL: URL? {
        source.fileURL ?? downloadedOriginalURL
    }

    /// True when the original bytes are not on this Mac, so full resolution,
    /// RAW decoding, and capture settings are unavailable until downloaded.
    var needsOriginalDownload: Bool {
        isPhotoKitAsset && downloadedOriginalURL == nil
    }

    var selectionKey: String {
        source.storageKey
    }

    /// Preview cache namespace. Downloading an original changes how the photo
    /// decodes, so it deliberately changes the key too.
    var previewSource: AssetSource {
        downloadedOriginalURL.map { AssetSource.file($0) } ?? source
    }
}

struct StoredSelection: Codable, Hashable, Sendable {
    var decision: PhotoDecision
}
