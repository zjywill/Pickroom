import Foundation

struct PhotoAsset: Identifiable, Hashable, Sendable {
    let id: UUID
    var url: URL
    var companionURL: URL?
    var decision: PhotoDecision
    var rating: Int
    var metadata: PhotoMetadata
    var isArchived: Bool

    init(
        id: UUID = UUID(),
        url: URL,
        companionURL: URL? = nil,
        decision: PhotoDecision = .unreviewed,
        rating: Int = 0,
        metadata: PhotoMetadata,
        isArchived: Bool = false
    ) {
        self.id = id
        self.url = url
        self.companionURL = companionURL
        self.decision = decision
        self.rating = rating
        self.metadata = metadata
        self.isArchived = isArchived
    }

    var filename: String {
        url.lastPathComponent
    }

    var selectionKey: String {
        url.standardizedFileURL.path
    }
}

struct StoredSelection: Codable, Hashable, Sendable {
    var decision: PhotoDecision
    var rating: Int
}
