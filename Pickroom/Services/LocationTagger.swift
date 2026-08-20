import Foundation

/// Which photos a location applies to.
enum LocationScope: Hashable, Sendable, CaseIterable {
    case current
    case selection
    case filtered
}

struct LocationTagResult: Sendable {
    var taggedAssetIDs: [UUID] = []
    var failures: [FileOperationFailure] = []
}

struct LocationClearResult: Sendable {
    var clearedAssetIDs: [UUID] = []
    /// Raw files whose camera wrote coordinates into the file itself. The
    /// sidecar is gone but the file still knows where it was taken, and
    /// nothing here can change that.
    var stillEmbedded: [String] = []
    var failures: [FileOperationFailure] = []
}

/// Writes one location onto many photos, off the main actor.
///
/// A wedding is one venue and eight hundred frames, so this is the shape the
/// work actually arrives in — tagging one photo is the special case, not the
/// other way round.
actor LocationTagger {
    func apply(_ location: PhotoLocation, to assets: [PhotoAsset]) -> LocationTagResult {
        var result = LocationTagResult()

        for asset in assets {
            guard let primaryURL = asset.fileURL else {
                result.failures.append(
                    FileOperationFailure(
                        filename: asset.filename,
                        reason: LocationWriteError.photosLibraryAsset.localizedDescription
                    )
                )
                continue
            }

            do {
                try PhotoLocationWriter.write(location, to: primaryURL)
                result.taggedAssetIDs.append(asset.id)
            } catch {
                result.failures.append(
                    FileOperationFailure(
                        filename: asset.filename,
                        reason: error.localizedDescription
                    )
                )
                continue
            }

            // A RAW and its JPEG are one photograph, so the JPEG gets the same
            // coordinates. Its own sidecar would be ignored by Adobe, so this
            // is an in-place write and can fail on its own terms.
            if let companionURL = asset.companionURL {
                do {
                    try PhotoLocationWriter.write(location, to: companionURL)
                } catch {
                    result.failures.append(
                        FileOperationFailure(
                            filename: companionURL.lastPathComponent,
                            reason: error.localizedDescription
                        )
                    )
                }
            }
        }

        return result
    }

    /// Strips coordinates from every photo that has any.
    ///
    /// Photos without one are skipped rather than rewritten: clearing a whole
    /// folder should not rewrite two thousand files that never had a location
    /// to begin with.
    func clear(from assets: [PhotoAsset]) -> LocationClearResult {
        var result = LocationClearResult()

        for asset in assets {
            guard let primaryURL = asset.fileURL else { continue }

            let urls = [primaryURL] + (asset.companionURL.map { [$0] } ?? [])
            var cleared = false

            for url in urls where PhotoLocationWriter.hasLocation(url) {
                do {
                    if try PhotoLocationWriter.clear(from: url) {
                        result.stillEmbedded.append(url.lastPathComponent)
                    }
                    cleared = true
                } catch {
                    result.failures.append(
                        FileOperationFailure(
                            filename: url.lastPathComponent,
                            reason: error.localizedDescription
                        )
                    )
                }
            }

            if cleared {
                result.clearedAssetIDs.append(asset.id)
            }
        }

        return result
    }
}
