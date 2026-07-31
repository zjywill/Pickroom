import SwiftUI

enum PhotoDecision: String, Codable, CaseIterable, Hashable, Sendable {
    case unreviewed
    case pick
    case maybe
    case reject

    var title: String {
        switch self {
        case .unreviewed: "Unreviewed"
        case .pick: "Pick"
        case .maybe: "Maybe"
        case .reject: "Reject"
        }
    }

    var shortTitle: String {
        switch self {
        case .unreviewed: "Unmarked"
        case .pick: "Pick"
        case .maybe: "Maybe"
        case .reject: "Reject"
        }
    }

    var symbol: String {
        switch self {
        case .unreviewed: "circle"
        case .pick: "checkmark.circle.fill"
        case .maybe: "questionmark.circle.fill"
        case .reject: "xmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .unreviewed: .secondary
        case .pick: Color(red: 0.20, green: 0.78, blue: 0.58)
        case .maybe: Color(red: 0.96, green: 0.67, blue: 0.20)
        case .reject: Color(red: 0.94, green: 0.31, blue: 0.34)
        }
    }
}

enum LibraryFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all
    case unreviewed
    case picks
    case maybes
    case rejects

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All Photos"
        case .unreviewed: "Unreviewed"
        case .picks: "Picks"
        case .maybes: "Maybes"
        case .rejects: "Rejects"
        }
    }

    var symbol: String {
        switch self {
        case .all: "photo.on.rectangle.angled"
        case .unreviewed: "circle.dotted"
        case .picks: "checkmark.circle.fill"
        case .maybes: "questionmark.circle.fill"
        case .rejects: "xmark.circle.fill"
        }
    }

    func matches(_ asset: PhotoAsset) -> Bool {
        switch self {
        case .all: true
        case .unreviewed: asset.decision == .unreviewed
        case .picks: asset.decision == .pick
        case .maybes: asset.decision == .maybe
        case .rejects: asset.decision == .reject
        }
    }
}

enum WorkspaceMode: String, CaseIterable, Identifiable, Sendable {
    case cull
    case grid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cull: "Cull"
        case .grid: "Grid"
        }
    }

    var symbol: String {
        switch self {
        case .cull: "rectangle.inset.filled"
        case .grid: "square.grid.3x3"
        }
    }
}
