import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    var assets: [PhotoAsset] = []
    var currentAssetID: UUID?
    private(set) var librarySource: LibrarySource = .none
    var photoAccess: PhotoKitAccess = .notDetermined
    private(set) var photoCollections: [PhotoCollection] = []
    private(set) var isDownloadingOriginal = false
    private(set) var downloadProgress: Double = 0
    var photoLibraryError: String?
    var filter: LibraryFilter = .all {
        didSet {
            ensureVisibleSelection()
        }
    }
    var workspaceMode: WorkspaceMode = .cull
    var compositionGridEnabled = false
    var zoomScale: CGFloat = 1
    private(set) var fitPixelScale: CGFloat = 1
    var isLoading = false
    var loadError: String?
    var fileOperationError: String?
    var isManagingRejects = false
    var isShowingTrashConfirmation = false

    private let scanner: PhotoLibraryScanner
    private let selectionStore: SelectionStore
    private let rejectedPhotoManager: RejectedPhotoManager
    private let folderAccess: FolderAccess
    private var storedSelections: [String: StoredSelection] = [:]
    private var selectionSaveTask: Task<Void, Never>?
    private var detailRequestedIDs: Set<UUID> = []

    init(
        scanner: PhotoLibraryScanner = PhotoLibraryScanner(),
        selectionStore: SelectionStore = SelectionStore(),
        rejectedPhotoManager: RejectedPhotoManager = RejectedPhotoManager(),
        userDefaults: UserDefaults = .standard
    ) {
        self.scanner = scanner
        self.selectionStore = selectionStore
        self.rejectedPhotoManager = rejectedPhotoManager
        self.folderAccess = FolderAccess(defaults: userDefaults)
    }

    var sourceFolder: URL? {
        librarySource.folderURL
    }

    var isPhotosSource: Bool {
        librarySource.isPhotos
    }

    var selectedCollectionID: PhotoCollectionID? {
        librarySource.collectionID
    }

    var filteredAssets: [PhotoAsset] {
        assets.filter(filter.matches)
    }

    var currentAsset: PhotoAsset? {
        guard let currentAssetID else { return nil }
        return assets.first(where: { $0.id == currentAssetID })
    }

    var currentVisibleIndex: Int? {
        guard let currentAssetID else { return nil }
        return filteredAssets.firstIndex(where: { $0.id == currentAssetID })
    }

    var sourceName: String {
        switch librarySource {
        case .none:
            "No source"
        case let .folder(url):
            url.lastPathComponent
        case let .photos(id):
            photoCollections.first(where: { $0.id == id })?.title ?? "Photos"
        }
    }

    var sourceSubtitle: String? {
        switch librarySource {
        case .none:
            nil
        case let .folder(url):
            url.deletingLastPathComponent().path
        case .photos:
            "Photos Library"
        }
    }

    var archivedAssetCount: Int {
        assets.count { $0.isArchived }
    }

    var rejectedAssetCount: Int {
        assets.count { $0.decision == .reject }
    }

    var rejectedFileCount: Int {
        assets
            .filter { $0.decision == .reject }
            .reduce(into: 0) { count, asset in
                count += asset.companionURL == nil ? 1 : 2
            }
    }

    /// The current photo needs its original downloaded before Pickroom can
    /// show full resolution pixels or capture settings.
    var currentAssetNeedsDownload: Bool {
        currentAsset?.needsOriginalDownload ?? false
    }

    var trashConfirmationTitle: String {
        isPhotosSource ? "Delete Rejected Photos?" : "Move Rejected Photos to Trash?"
    }

    var trashConfirmationMessage: String {
        let photoLabel = rejectedAssetCount == 1 ? "photo" : "photos"

        if isPhotosSource {
            return "\(rejectedAssetCount) rejected \(photoLabel) "
                + "will be moved to Recently Deleted in Photos. "
                + "Photos asks for its own confirmation, and the \(photoLabel) "
                + "stay recoverable there for 30 days."
        }

        let fileLabel = rejectedFileCount == 1 ? "file" : "files"
        let pairedFileNote = rejectedFileCount > rejectedAssetCount
            ? ", including paired files"
            : ""
        return "\(rejectedAssetCount) rejected \(photoLabel) "
            + "(\(rejectedFileCount) \(fileLabel)\(pairedFileNote)) "
            + "will be moved to macOS Trash. "
            + "You can recover them from Trash until it is emptied."
    }

    var actualPixelScale: CGFloat {
        fitPixelScale * zoomScale
    }

    var maximumZoomScale: CGFloat {
        min(max(8, 2 / max(fitPixelScale, 0.001)), 32)
    }

    var zoomDisplayLabel: String {
        ZoomMath.displayLabel(
            zoomScale: zoomScale,
            actualPixelScale: actualPixelScale
        )
    }

    func count(for filter: LibraryFilter) -> Int {
        assets.filter(filter.matches).count
    }

    func openFolder() {
        guard !isLoading else { return }

        let panel = NSOpenPanel()
        panel.title = "Choose a photo folder"
        panel.message = "Pickroom only moves rejected files after you confirm sending them to Trash."
        panel.prompt = "Open Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let folder = panel.url else { return }
        Task {
            await loadFolder(folder)
        }
    }

    func loadDroppedURLs(_ urls: [URL]) {
        guard !isLoading else { return }
        guard let dropped = urls.first else { return }

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: dropped.path,
            isDirectory: &isDirectory
        )
        if exists, isDirectory.boolValue {
            Task { await loadFolder(dropped) }
            return
        }

        // The sandbox grants access to exactly what was dragged. A dropped
        // photo does not bring its folder along, so the enclosing folder can
        // be unreadable even though its path is right there in the URL —
        // check before scanning, or the folder reads as empty and the error
        // blames the photos.
        let folder = dropped.deletingLastPathComponent()
        guard (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) != nil else {
            loadError = "Drag in the folder itself. Dropping a photo lets "
                + "Pickroom see only that one file, not the rest of the folder."
            return
        }
        Task { await loadFolder(folder) }
    }

    func loadFolder(_ folder: URL) async {
        guard !isLoading else { return }
        isLoading = true
        loadError = nil

        await selectionSaveTask?.value
        storedSelections = await selectionStore.load()
        var scanned = await scanner.scan(folder: folder)
        for index in scanned.indices {
            if let stored = storedSelections[scanned[index].selectionKey] {
                scanned[index].decision = stored.decision
                scanned[index].rating = stored.rating
            }
        }

        librarySource = .folder(folder)
        assets = scanned
        detailRequestedIDs.removeAll()
        filter = .all
        resetZoom()
        fitPixelScale = 1
        currentAssetID = scanned.first?.id
        workspaceMode = .cull
        isLoading = false

        folderAccess.remember(folder)

        if scanned.isEmpty {
            loadError = "No supported RAW or image files were found in “\(folder.lastPathComponent)”."
        }
    }

    func restoreLastFolderIfAvailable() async {
        guard assets.isEmpty, let folder = folderAccess.restoreRemembered() else { return }
        await loadFolder(folder)
    }

    // MARK: - Photos library

    /// Asks for photo library access the first time and opens the library.
    ///
    /// Never called automatically at launch: the system access prompt should
    /// only appear because the user asked for the Photos library.
    func openPhotosLibrary() async {
        guard !isLoading else { return }
        photoLibraryError = nil

        let access = await PhotoKitLibrary.shared.requestAccess()
        photoAccess = access

        guard access.canRead else {
            photoLibraryError = access.explanation
            return
        }

        isLoading = true
        let collections = await PhotoKitLibrary.shared.collections()
        photoCollections = collections
        isLoading = false

        guard let first = collections.first else {
            photoLibraryError = "Your photo library has no photos Pickroom can show."
            return
        }

        await loadCollection(first)
    }

    func loadCollection(_ collection: PhotoCollection) async {
        guard !isLoading, photoAccess.canRead else { return }
        isLoading = true
        loadError = nil
        photoLibraryError = nil

        await selectionSaveTask?.value
        storedSelections = await selectionStore.load()
        var fetched = await PhotoKitLibrary.shared.assets(in: collection.id)
        for index in fetched.indices {
            if let stored = storedSelections[fetched[index].selectionKey] {
                fetched[index].decision = stored.decision
                fetched[index].rating = stored.rating
            }
        }

        librarySource = .photos(collection.id)
        assets = fetched
        detailRequestedIDs.removeAll()
        filter = .all
        resetZoom()
        fitPixelScale = 1
        currentAssetID = fetched.first?.id
        workspaceMode = .cull
        isLoading = false

        if fetched.isEmpty {
            loadError = "“\(collection.title)” has no photos Pickroom can show."
        }
    }

    /// Fills in the original filename and RAW flag for one Photos asset.
    /// Reads PhotoKit's local records only, so it never triggers a download.
    func resolveDetailsIfNeeded(for asset: PhotoAsset) {
        guard
            let identifier = asset.source.localIdentifier,
            asset.metadata.requiresOriginalForDetails,
            !detailRequestedIDs.contains(asset.id)
        else {
            return
        }

        detailRequestedIDs.insert(asset.id)
        let assetID = asset.id
        Task {
            let details = await PhotoKitLibrary.shared.resourceDetails(
                localIdentifier: identifier
            )
            applyResourceDetails(details, to: assetID)
        }
    }

    private func applyResourceDetails(_ details: PhotoResourceDetails?, to assetID: UUID) {
        guard
            let details,
            let index = assets.firstIndex(where: { $0.id == assetID })
        else {
            return
        }

        assets[index].filename = details.filename
        assets[index].metadata.isRaw = details.isRaw
        if !details.fileExtension.isEmpty {
            assets[index].metadata.fileExtension = details.fileExtension.uppercased()
        }
    }

    /// Downloads the current photo's original from iCloud. This is the only
    /// place Pickroom uses the network, and only on an explicit request.
    func downloadCurrentOriginal() async {
        guard
            !isLoading,
            !isDownloadingOriginal,
            let asset = currentAsset,
            let identifier = asset.source.localIdentifier,
            asset.downloadedOriginalURL == nil
        else {
            return
        }

        isDownloadingOriginal = true
        downloadProgress = 0
        photoLibraryError = nil

        do {
            let url = try await PhotoKitLibrary.shared.downloadOriginal(
                localIdentifier: identifier,
                progress: { [weak self] value in
                    Task { @MainActor in
                        self?.downloadProgress = value
                    }
                }
            )
            let isRaw = PhotoLibraryScanner.isRaw(url)
            let metadata = await Task.detached {
                MetadataReader.read(from: url, isRaw: isRaw)
            }.value
            applyDownloadedOriginal(url, metadata: metadata, to: asset.id)
        } catch {
            photoLibraryError = error.localizedDescription
        }

        isDownloadingOriginal = false
        downloadProgress = 0
    }

    private func applyDownloadedOriginal(
        _ url: URL,
        metadata: PhotoMetadata,
        to assetID: UUID
    ) {
        guard let index = assets.firstIndex(where: { $0.id == assetID }) else { return }

        var resolved = metadata
        resolved.requiresOriginalForDetails = false
        assets[index].downloadedOriginalURL = url
        assets[index].filename = url.lastPathComponent
        assets[index].metadata = resolved
    }

    private func deleteRejectedPhotosFromLibrary() async {
        let candidates = assets.filter { $0.decision == .reject }
        guard !candidates.isEmpty else { return }

        isShowingTrashConfirmation = false
        isManagingRejects = true
        fileOperationError = nil

        do {
            try await PhotoKitLibrary.shared.delete(
                localIdentifiers: candidates.compactMap { $0.source.localIdentifier }
            )

            for candidate in candidates {
                storedSelections.removeValue(forKey: candidate.selectionKey)
                if let downloaded = candidate.downloadedOriginalURL {
                    PhotoKitLibrary.shared.discardDownloadedOriginal(at: downloaded)
                }
            }
            await saveStoredSelections()

            let removedIDs = Set(candidates.map(\.id))
            assets.removeAll { removedIDs.contains($0.id) }
            currentAssetID = nil
            ensureVisibleSelection()
        } catch PhotoKitError.cancelled {
            // Photos asked, the user said no. Leave the decisions untouched.
        } catch {
            fileOperationError = error.localizedDescription
        }

        isManagingRejects = false
    }

    func select(_ asset: PhotoAsset) {
        guard !isLoading else { return }
        currentAssetID = asset.id
    }

    func selectNext() {
        guard !isLoading else { return }
        moveSelection(by: 1)
    }

    func selectPrevious() {
        guard !isLoading else { return }
        moveSelection(by: -1)
    }

    func setDecision(_ decision: PhotoDecision, advance: Bool = true) {
        guard
            !isLoading,
            !isManagingRejects,
            let currentAssetID,
            let assetIndex = assets.firstIndex(where: { $0.id == currentAssetID })
        else {
            return
        }

        let nextID = nextVisibleID(after: assetIndex)
        let shouldRestore = assets[assetIndex].isArchived && decision != .reject
        let changedAssetID = assets[assetIndex].id
        assets[assetIndex].decision = decision
        persistSelection(for: assets[assetIndex])

        if advance {
            if let nextID, filteredAssets.contains(where: { $0.id == nextID }) {
                self.currentAssetID = nextID
            } else {
                ensureVisibleSelection()
            }
        }

        if shouldRestore {
            Task {
                await restoreCollectedPhotos(assetIDs: [changedAssetID])
            }
        }
    }

    func setRating(_ rating: Int) {
        guard
            !isLoading,
            let currentAssetID,
            let index = assets.firstIndex(where: { $0.id == currentAssetID })
        else {
            return
        }

        assets[index].rating = min(max(rating, 0), 5)
        persistSelection(for: assets[index])
    }

    private func restoreCollectedPhotos(assetIDs: Set<UUID>?) async {
        guard
            !isLoading,
            !isManagingRejects,
            let sourceFolder
        else {
            return
        }

        let candidates = assets.filter {
            $0.isArchived && (assetIDs?.contains($0.id) ?? true)
        }
        guard !candidates.isEmpty else { return }

        isManagingRejects = true
        fileOperationError = nil
        let result = await rejectedPhotoManager.restore(candidates, to: sourceFolder)
        applyRelocations(result.relocations, isArchived: false)
        await saveStoredSelections()
        isManagingRejects = false
        presentFailures(result.failures, action: "restore")
    }

    func requestTrashConfirmation() {
        guard rejectedAssetCount > 0, !isManagingRejects else { return }
        isShowingTrashConfirmation = true
    }

    func moveRejectedPhotosToTrash() async {
        guard !isLoading, !isManagingRejects else { return }

        if isPhotosSource {
            await deleteRejectedPhotosFromLibrary()
            return
        }

        guard let sourceFolder else { return }

        let candidates = assets.filter { $0.decision == .reject }
        guard !candidates.isEmpty else { return }

        isShowingTrashConfirmation = false
        isManagingRejects = true
        fileOperationError = nil

        let preferredSelectionKey = currentAsset?.selectionKey
        let result = await rejectedPhotoManager.moveToTrash(candidates)
        migrateSelectionsForRemainingFiles(in: candidates)
        await saveStoredSelections()
        await reloadAssetsAfterFileOperation(
            sourceFolder: sourceFolder,
            preferredSelectionKey: preferredSelectionKey
        )

        isManagingRejects = false
        presentFailures(result.failures, action: "move to Trash")
    }

    func toggleCompositionGrid() {
        guard !isLoading else { return }
        compositionGridEnabled.toggle()
    }

    func setZoom(_ value: CGFloat) {
        zoomScale = min(max(value, 1), maximumZoomScale)
    }

    func updateFitPixelScale(_ value: CGFloat) {
        let newValue = max(value, 0.001)
        guard abs(newValue - fitPixelScale) > 0.0001 else { return }

        let preservedActualScale = actualPixelScale
        let wasFit = zoomScale <= 1.001
        fitPixelScale = newValue

        if wasFit {
            zoomScale = 1
        } else {
            setZoom(preservedActualScale / newValue)
        }
    }

    func zoomIn() {
        setZoom(zoomScale * 1.25)
    }

    func zoomOut() {
        setZoom(zoomScale / 1.25)
    }

    func resetZoom() {
        zoomScale = 1
    }

    func zoomToActualSize() {
        setZoom(1 / max(fitPixelScale, 0.001))
    }

    /// Switches between the fitted view and 100% pixels, matching the
    /// double-click gesture on the canvas.
    func toggleActualSize() {
        guard !isLoading, currentAsset != nil else { return }

        if zoomScale > 1.001 {
            resetZoom()
        } else {
            zoomToActualSize()
        }
    }

    func neighboringAssets(limit: Int = 1) -> [PhotoAsset] {
        guard let currentVisibleIndex else { return [] }

        let lowerBound = max(currentVisibleIndex - limit, 0)
        let upperBound = min(currentVisibleIndex + limit, filteredAssets.count - 1)
        guard lowerBound <= upperBound else { return [] }

        return filteredAssets[lowerBound...upperBound].filter { $0.id != currentAssetID }
    }

    private func moveSelection(by offset: Int) {
        let visible = filteredAssets
        guard !visible.isEmpty else {
            currentAssetID = nil
            return
        }

        let currentIndex = currentVisibleIndex ?? 0
        let target = min(max(currentIndex + offset, 0), visible.count - 1)
        currentAssetID = visible[target].id
    }

    private func nextVisibleID(after assetIndex: Int) -> UUID? {
        guard !assets.isEmpty else { return nil }

        if assetIndex + 1 < assets.count,
           let next = assets[(assetIndex + 1)...].first(where: filter.matches) {
            return next.id
        }

        if assetIndex > 0,
           let previous = assets[..<assetIndex].reversed().first(where: filter.matches) {
            return previous.id
        }

        return nil
    }

    private func ensureVisibleSelection() {
        let visible = filteredAssets
        guard !visible.isEmpty else {
            currentAssetID = nil
            return
        }

        if let currentAssetID, visible.contains(where: { $0.id == currentAssetID }) {
            return
        }
        currentAssetID = visible.first?.id
    }

    private func persistSelection(for asset: PhotoAsset) {
        storedSelections[asset.selectionKey] = StoredSelection(
            decision: asset.decision,
            rating: asset.rating
        )
        let snapshot = storedSelections
        let pendingSave = selectionSaveTask
        selectionSaveTask = Task {
            await pendingSave?.value
            await selectionStore.save(snapshot)
        }
    }

    private func applyRelocations(_ relocations: [PhotoRelocation], isArchived: Bool) {
        var selectionMoves: [StoredSelectionKeyMove] = []

        for relocation in relocations {
            guard let index = assets.firstIndex(where: { $0.id == relocation.assetID }) else {
                continue
            }

            let asset = assets[index]
            let selection = storedSelections[asset.selectionKey] ?? StoredSelection(
                decision: asset.decision,
                rating: asset.rating
            )

            selectionMoves.append(
                StoredSelectionKeyMove(
                    sourceKey: relocation.sourceURL.standardizedFileURL.path,
                    destinationKey: relocation.destinationURL.standardizedFileURL.path,
                    selection: selection
                )
            )

            assets[index].source = .file(relocation.destinationURL)
            assets[index].filename = relocation.destinationURL.lastPathComponent
            assets[index].companionURL = relocation.destinationCompanionURL
            assets[index].isArchived = isArchived
        }

        storedSelections = StoredSelectionKeyMigration.applying(
            selectionMoves,
            to: storedSelections
        )
    }

    private func migrateSelectionsForRemainingFiles(in candidates: [PhotoAsset]) {
        for asset in candidates {
            guard let primaryURL = asset.fileURL else { continue }
            let primaryKey = asset.selectionKey
            let selection = storedSelections[primaryKey] ?? StoredSelection(
                decision: asset.decision,
                rating: asset.rating
            )
            let primaryExists = FileManager.default.fileExists(atPath: primaryURL.path)
            let companionExists = asset.companionURL.map {
                FileManager.default.fileExists(atPath: $0.path)
            } ?? false

            if !primaryExists {
                storedSelections.removeValue(forKey: primaryKey)
            }
            if !primaryExists, companionExists, let companionURL = asset.companionURL {
                storedSelections[companionURL.standardizedFileURL.path] = selection
            }
        }
    }

    private func reloadAssetsAfterFileOperation(
        sourceFolder: URL,
        preferredSelectionKey: String?
    ) async {
        var scanned = await scanner.scan(folder: sourceFolder)
        for index in scanned.indices {
            if let stored = storedSelections[scanned[index].selectionKey] {
                scanned[index].decision = stored.decision
                scanned[index].rating = stored.rating
            }
        }

        assets = scanned
        detailRequestedIDs.removeAll()
        if let preferredSelectionKey,
           let preferred = scanned.first(where: {
               $0.selectionKey == preferredSelectionKey
           }) {
            currentAssetID = preferred.id
        } else {
            currentAssetID = nil
            ensureVisibleSelection()
        }
    }

    private func saveStoredSelections() async {
        await selectionSaveTask?.value
        await selectionStore.save(storedSelections)
    }

    private func presentFailures(_ failures: [RejectOperationFailure], action: String) {
        guard !failures.isEmpty else { return }

        let details = failures.prefix(3).map {
            "\($0.filename): \($0.reason)"
        }
        let remaining = failures.count - details.count
        let suffix = remaining > 0 ? "\n…and \(remaining) more." : ""
        fileOperationError = "Could not \(action) \(failures.count) photo"
            + (failures.count == 1 ? "" : "s")
            + ".\n\n"
            + details.joined(separator: "\n")
            + suffix
    }
}

struct StoredSelectionKeyMove: Hashable, Sendable {
    let sourceKey: String
    let destinationKey: String
    let selection: StoredSelection
}

enum StoredSelectionKeyMigration {
    static func applying(
        _ moves: [StoredSelectionKeyMove],
        to selections: [String: StoredSelection]
    ) -> [String: StoredSelection] {
        var migrated = selections

        for move in moves {
            migrated.removeValue(forKey: move.sourceKey)
            migrated[move.destinationKey] = move.selection
        }

        return migrated
    }
}

enum ZoomMath {
    static func fitPixelScale(
        imageRect: CGRect,
        sourcePixelSize: CGSize,
        displayScale: CGFloat
    ) -> CGFloat {
        let sourceLongEdge = max(sourcePixelSize.width, sourcePixelSize.height)
        let displayedLongEdge = max(imageRect.width, imageRect.height) * displayScale
        guard sourceLongEdge > 0, displayedLongEdge > 0 else { return 1 }
        return displayedLongEdge / sourceLongEdge
    }

    static func anchoredOffset(
        currentOffset: CGSize,
        imageCenter: CGPoint,
        anchor: CGPoint,
        scaleRatio: CGFloat
    ) -> CGSize {
        CGSize(
            width: anchor.x - imageCenter.x
                - (anchor.x - imageCenter.x - currentOffset.width) * scaleRatio,
            height: anchor.y - imageCenter.y
                - (anchor.y - imageCenter.y - currentOffset.height) * scaleRatio
        )
    }

    static func displayLabel(zoomScale: CGFloat, actualPixelScale: CGFloat) -> String {
        if zoomScale <= 1.001 {
            return "Fit"
        }
        if abs(actualPixelScale - 1) <= 0.015 {
            return "1:1"
        }
        return "\(Int((actualPixelScale * 100).rounded()))%"
    }
}
