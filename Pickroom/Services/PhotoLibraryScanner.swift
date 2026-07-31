import Foundation
import UniformTypeIdentifiers

actor PhotoLibraryScanner {
    static let rawExtensions: Set<String> = [
        "3fr", "arw", "cr2", "cr3", "dcr", "dng", "erf", "fff", "iiq",
        "kdc", "mef", "mos", "mrw", "nef", "nrw", "orf", "pef", "raf",
        "raw", "rw2", "rwl", "sr2", "srf", "srw", "x3f"
    ]

    static let commonImageExtensions: Set<String> = [
        "avif", "heic", "heif", "jpeg", "jpg", "png", "svg", "tif", "tiff", "webp"
    ]

    func scan(folder: URL) -> [PhotoAsset] {
        let activeAssets = Self.assets(
            from: Self.imageURLs(in: folder),
            isArchived: false
        )
        let archivedAssets = Self.assets(
            from: Self.imageURLs(in: RejectArchive.folder(in: folder)),
            isArchived: true
        )

        return activeAssets + archivedAssets
    }

    private static func assets(from urls: [URL], isArchived: Bool) -> [PhotoAsset] {
        let pairs = preferredPhotoPairs(from: urls)
        return pairs.map { primary, companion in
            let isRaw = isRaw(primary)
            return PhotoAsset(
                url: primary,
                companionURL: companion,
                decision: isArchived ? .reject : .unreviewed,
                metadata: MetadataReader.read(from: primary, isRaw: isRaw),
                isArchived: isArchived
            )
        }
    }

    static func isSupported(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else { return false }

        if rawExtensions.contains(ext) || commonImageExtensions.contains(ext) {
            return true
        }

        return UTType(filenameExtension: ext)?.conforms(to: .image) == true
    }

    static func isRaw(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if rawExtensions.contains(ext) {
            return true
        }
        return UTType(filenameExtension: ext)?.conforms(to: .rawImage) == true
    }

    static func preferredPhotoPairs(from urls: [URL]) -> [(URL, URL?)] {
        let grouped = Dictionary(grouping: urls) {
            $0.deletingPathExtension().standardizedFileURL.path.lowercased()
        }

        return grouped.values.compactMap { group in
            let sorted = group.sorted {
                if isRaw($0) != isRaw($1) {
                    return isRaw($0)
                }
                return $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }

            guard let primary = sorted.first else { return nil }
            let companion = isRaw(primary) ? sorted.dropFirst().first(where: { !isRaw($0) }) : nil
            return (primary, companion)
        }
        .sorted {
            $0.0.lastPathComponent.localizedStandardCompare($1.0.lastPathComponent) == .orderedAscending
        }
    }

    private static func imageURLs(in folder: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            guard isSupported(url) else { continue }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isHiddenKey])
            guard values?.isRegularFile == true, values?.isHidden != true else { continue }
            urls.append(url)
        }
        return urls
    }
}
