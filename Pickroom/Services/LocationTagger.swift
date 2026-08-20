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
}
