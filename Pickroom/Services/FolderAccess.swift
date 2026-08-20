import Foundation

/// Remembers the folder the user last culled, in a form the sandbox honours.
///
/// A path string survives a relaunch but the permission behind it does not:
/// the sandbox grants access to what the user picked in *this* launch, and a
/// path reconstructed from defaults is just a string the app has no claim to.
/// A security-scoped bookmark is the claim itself, which is why the folder is
/// stored as one.
///
/// The claim taken in ``restoreRemembered()`` is deliberately never dropped.
/// It costs one kernel extension for the process lifetime, and releasing it
/// when the user opens a second folder would be a bug the first time someone
/// reopens the folder they started in.
@MainActor
final class FolderAccess {
    private static let bookmarkKey = "lastPhotoFolderBookmark"

    private let defaults: UserDefaults
    private var claimed: URL?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Records `folder` so a later launch can reopen it.
    func remember(_ folder: URL) {
        guard
            let data = try? folder.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        else {
            return
        }
        defaults.set(data, forKey: Self.bookmarkKey)
    }

    /// Resolves the remembered folder and claims access to it.
    ///
    /// Returns nil when nothing was remembered, when the folder has since
    /// moved beyond what the bookmark can follow, or when the claim is
    /// refused — in which case the stale bookmark is discarded rather than
    /// retried on every launch.
    func restoreRemembered() -> URL? {
        guard let data = defaults.data(forKey: Self.bookmarkKey) else { return nil }

        var isStale = false
        guard
            let url = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ),
            url.startAccessingSecurityScopedResource()
        else {
            defaults.removeObject(forKey: Self.bookmarkKey)
            return nil
        }

        claimed?.stopAccessingSecurityScopedResource()
        claimed = url

        // A stale bookmark still resolves, but only once more. Rewriting it
        // while the claim is held is the only chance to keep the folder.
        if isStale {
            remember(url)
        }
        return url
    }
}
