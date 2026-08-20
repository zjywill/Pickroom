import Foundation

enum RejectArchive {
    static let directoryName = ".pickroom-rejects"

    static func folder(in sourceFolder: URL) -> URL {
        sourceFolder.appendingPathComponent(directoryName, isDirectory: true)
    }
}

struct PhotoRelocation: Hashable, Sendable {
    let assetID: UUID
    let sourceURL: URL
    let destinationURL: URL
    let sourceCompanionURL: URL?
    let destinationCompanionURL: URL?
}

/// One file an operation could not finish, named so the user can go look
/// at it. Reject moves and location writes both report through this.
struct FileOperationFailure: Hashable, Sendable {
    let filename: String
    let reason: String
}

struct RejectRelocationResult: Sendable {
    var relocations: [PhotoRelocation] = []
    var failures: [FileOperationFailure] = []
}

struct RejectTrashResult: Sendable {
    var completedAssetIDs: [UUID] = []
    var failures: [FileOperationFailure] = []
}

protocol TrashMoving: Sendable {
    func moveToTrash(_ urls: [URL]) async throws
}

struct MacOSTrashMover: TrashMoving {
    func moveToTrash(_ urls: [URL]) async throws {
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            var resultingURL: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        }
    }
}

actor RejectedPhotoManager {
    private let fileManager: FileManager
    private let trashMover: any TrashMoving

    init(
        fileManager: FileManager = .default,
        trashMover: any TrashMoving = MacOSTrashMover()
    ) {
        self.fileManager = fileManager
        self.trashMover = trashMover
    }

    func collect(_ assets: [PhotoAsset], in sourceFolder: URL) -> RejectRelocationResult {
        relocate(
            assets,
            sourceRoot: sourceFolder,
            destinationRoot: RejectArchive.folder(in: sourceFolder)
        )
    }

    func restore(_ assets: [PhotoAsset], to sourceFolder: URL) -> RejectRelocationResult {
        relocate(
            assets,
            sourceRoot: RejectArchive.folder(in: sourceFolder),
            destinationRoot: sourceFolder
        )
    }

    func moveToTrash(_ assets: [PhotoAsset]) async -> RejectTrashResult {
        var result = RejectTrashResult()

        for asset in assets {
            guard let primaryURL = asset.fileURL else {
                result.failures.append(
                    FileOperationFailure(
                        filename: asset.filename,
                        reason: RejectFileError.notAFileAsset.localizedDescription
                    )
                )
                continue
            }
            let urls = [primaryURL, asset.companionURL].compactMap { $0 }

            do {
                try await trashMover.moveToTrash(urls)
                result.completedAssetIDs.append(asset.id)
            } catch {
                result.failures.append(
                    FileOperationFailure(
                        filename: asset.filename,
                        reason: error.localizedDescription
                    )
                )
            }
        }

        return result
    }

    private func relocate(
        _ assets: [PhotoAsset],
        sourceRoot: URL,
        destinationRoot: URL
    ) -> RejectRelocationResult {
        var result = RejectRelocationResult()

        for asset in assets {
            do {
                guard let primaryURL = asset.fileURL else {
                    throw RejectFileError.notAFileAsset
                }
                let sourceURLs = [primaryURL, asset.companionURL].compactMap { $0 }
                let proposedURLs = try sourceURLs.map {
                    destinationRoot.appendingPathComponent(
                        try relativePath(of: $0, inside: sourceRoot)
                    )
                }
                let destinationURLs = collisionFreeDestinations(for: proposedURLs)

                try moveGroup(from: sourceURLs, to: destinationURLs)

                result.relocations.append(
                    PhotoRelocation(
                        assetID: asset.id,
                        sourceURL: primaryURL,
                        destinationURL: destinationURLs[0],
                        sourceCompanionURL: asset.companionURL,
                        destinationCompanionURL: destinationURLs.count > 1
                            ? destinationURLs[1]
                            : nil
                    )
                )
            } catch {
                result.failures.append(
                    FileOperationFailure(
                        filename: asset.filename,
                        reason: error.localizedDescription
                    )
                )
            }
        }

        return result
    }

    private func relativePath(of url: URL, inside root: URL) throws -> String {
        let fileComponents = url.standardizedFileURL.pathComponents
        let rootComponents = root.standardizedFileURL.pathComponents

        guard
            fileComponents.count > rootComponents.count,
            Array(fileComponents.prefix(rootComponents.count)) == rootComponents
        else {
            throw RejectFileError.outsideSourceFolder(url)
        }

        return fileComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }

    private func collisionFreeDestinations(for proposedURLs: [URL]) -> [URL] {
        var suffix = 0

        while true {
            let candidates = proposedURLs.map { destination in
                suffix == 0 ? destination : destination.appendingFilenameSuffix(" (\(suffix))")
            }

            if candidates.allSatisfy({ !fileManager.fileExists(atPath: $0.path) }) {
                return candidates
            }

            suffix += 1
        }
    }

    private func moveGroup(from sourceURLs: [URL], to destinationURLs: [URL]) throws {
        var completedMoves: [(source: URL, destination: URL)] = []

        do {
            for destination in destinationURLs {
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
            }

            for (source, destination) in zip(sourceURLs, destinationURLs) {
                try fileManager.moveItem(at: source, to: destination)
                completedMoves.append((source, destination))
            }
        } catch {
            var rollbackFailures: [String] = []

            for move in completedMoves.reversed() {
                do {
                    try fileManager.moveItem(at: move.destination, to: move.source)
                } catch {
                    rollbackFailures.append(move.destination.path)
                }
            }

            if rollbackFailures.isEmpty {
                throw error
            }

            throw RejectFileError.rollbackFailed(paths: rollbackFailures)
        }
    }
}

private enum RejectFileError: LocalizedError {
    case notAFileAsset
    case outsideSourceFolder(URL)
    case rollbackFailed(paths: [String])

    var errorDescription: String? {
        switch self {
        case .notAFileAsset:
            "Photos library items are managed by Photos, not by moving files."
        case let .outsideSourceFolder(url):
            "“\(url.lastPathComponent)” is outside the selected source folder."
        case let .rollbackFailed(paths):
            "The move could not be fully rolled back. Check: \(paths.joined(separator: ", "))."
        }
    }
}

private extension URL {
    func appendingFilenameSuffix(_ suffix: String) -> URL {
        let ext = pathExtension
        let base = deletingPathExtension().lastPathComponent
        let filename = ext.isEmpty ? "\(base)\(suffix)" : "\(base)\(suffix).\(ext)"
        return deletingLastPathComponent().appendingPathComponent(filename)
    }
}
