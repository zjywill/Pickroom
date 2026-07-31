import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    var assets: [PhotoAsset] = []
    var currentAssetID: UUID?
    var sourceFolder: URL?
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
    private let userDefaults: UserDefaults
    private var storedSelections: [String: StoredSelection] = [:]
    private var selectionSaveTask: Task<Void, Never>?

    init(
        scanner: PhotoLibraryScanner = PhotoLibraryScanner(),
        selectionStore: SelectionStore = SelectionStore(),
        rejectedPhotoManager: RejectedPhotoManager = RejectedPhotoManager(),
        userDefaults: UserDefaults = .standard
    ) {
        self.scanner = scanner
        self.selectionStore = selectionStore
        self.rejectedPhotoManager = rejectedPhotoManager
        self.userDefaults = userDefaults
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
        sourceFolder?.lastPathComponent ?? "No folder"
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

    var trashConfirmationMessage: String {
        let photoLabel = rejectedAssetCount == 1 ? "photo" : "photos"
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
        guard let folder = urls.first.map(folderURL(for:)) else { return }
        Task {
            await loadFolder(folder)
        }
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

        sourceFolder = folder
        assets = scanned
        filter = .all
        resetZoom()
        fitPixelScale = 1
        currentAssetID = scanned.first?.id
        workspaceMode = .cull
        isLoading = false

        userDefaults.set(folder.path, forKey: "lastPhotoFolder")

        if scanned.isEmpty {
            loadError = "No supported RAW or image files were found in “\(folder.lastPathComponent)”."
        }
    }

    func restoreLastFolderIfAvailable() async {
        guard
            assets.isEmpty,
            let path = userDefaults.string(forKey: "lastPhotoFolder"),
            FileManager.default.fileExists(atPath: path)
        else {
            return
        }
        await loadFolder(URL(fileURLWithPath: path, isDirectory: true))
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
        guard
            !isLoading,
            !isManagingRejects,
            let sourceFolder
        else {
            return
        }

        let candidates = assets.filter { $0.decision == .reject }
        guard !candidates.isEmpty else { return }

        isShowingTrashConfirmation = false
        isManagingRejects = true
        fileOperationError = nil

        let preferredSelectionPath = currentAsset?.url.standardizedFileURL.path
        let result = await rejectedPhotoManager.moveToTrash(candidates)
        migrateSelectionsForRemainingFiles(in: candidates)
        await saveStoredSelections()
        await reloadAssetsAfterFileOperation(
            sourceFolder: sourceFolder,
            preferredSelectionPath: preferredSelectionPath
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

            assets[index].url = relocation.destinationURL
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
            let primaryKey = asset.selectionKey
            let selection = storedSelections[primaryKey] ?? StoredSelection(
                decision: asset.decision,
                rating: asset.rating
            )
            let primaryExists = FileManager.default.fileExists(atPath: asset.url.path)
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
        preferredSelectionPath: String?
    ) async {
        var scanned = await scanner.scan(folder: sourceFolder)
        for index in scanned.indices {
            if let stored = storedSelections[scanned[index].selectionKey] {
                scanned[index].decision = stored.decision
                scanned[index].rating = stored.rating
            }
        }

        assets = scanned
        if let preferredSelectionPath,
           let preferred = scanned.first(where: {
               $0.url.standardizedFileURL.path == preferredSelectionPath
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

    private func folderURL(for url: URL) -> URL {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return url
        }
        return url.deletingLastPathComponent()
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
