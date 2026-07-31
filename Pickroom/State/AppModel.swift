import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    var assets: [PhotoAsset] = []
    var currentAssetID: UUID? {
        didSet {
            if currentAssetID != oldValue {
                zoomScale = 1
            }
        }
    }
    var sourceFolder: URL?
    var filter: LibraryFilter = .all {
        didSet {
            ensureVisibleSelection()
        }
    }
    var workspaceMode: WorkspaceMode = .cull
    var compositionGridEnabled = false
    var zoomScale: CGFloat = 1
    var isLoading = false
    var loadError: String?

    private let scanner = PhotoLibraryScanner()
    private let selectionStore = SelectionStore()
    private var storedSelections: [String: StoredSelection] = [:]

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

    func count(for filter: LibraryFilter) -> Int {
        assets.filter(filter.matches).count
    }

    func openFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a photo folder"
        panel.message = "Pickroom reads the folder in place and does not modify source files."
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
        guard let folder = urls.first.map(folderURL(for:)) else { return }
        Task {
            await loadFolder(folder)
        }
    }

    func loadFolder(_ folder: URL) async {
        isLoading = true
        loadError = nil

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
        currentAssetID = scanned.first?.id
        workspaceMode = .cull
        isLoading = false

        UserDefaults.standard.set(folder.path, forKey: "lastPhotoFolder")

        if scanned.isEmpty {
            loadError = "No supported RAW or image files were found in “\(folder.lastPathComponent)”."
        }
    }

    func restoreLastFolderIfAvailable() async {
        guard
            assets.isEmpty,
            let path = UserDefaults.standard.string(forKey: "lastPhotoFolder"),
            FileManager.default.fileExists(atPath: path)
        else {
            return
        }
        await loadFolder(URL(fileURLWithPath: path, isDirectory: true))
    }

    func select(_ asset: PhotoAsset) {
        currentAssetID = asset.id
    }

    func selectNext() {
        moveSelection(by: 1)
    }

    func selectPrevious() {
        moveSelection(by: -1)
    }

    func setDecision(_ decision: PhotoDecision, advance: Bool = true) {
        guard
            let currentAssetID,
            let assetIndex = assets.firstIndex(where: { $0.id == currentAssetID })
        else {
            return
        }

        let nextID = nextVisibleID(after: assetIndex)
        assets[assetIndex].decision = decision
        persistSelection(for: assets[assetIndex])

        if advance {
            if let nextID, filteredAssets.contains(where: { $0.id == nextID }) {
                self.currentAssetID = nextID
            } else {
                ensureVisibleSelection()
            }
        }
    }

    func setRating(_ rating: Int) {
        guard
            let currentAssetID,
            let index = assets.firstIndex(where: { $0.id == currentAssetID })
        else {
            return
        }

        assets[index].rating = min(max(rating, 0), 5)
        persistSelection(for: assets[index])
    }

    func toggleCompositionGrid() {
        compositionGridEnabled.toggle()
    }

    func setZoom(_ value: CGFloat) {
        zoomScale = min(max(value, 1), 8)
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
        Task {
            await selectionStore.save(snapshot)
        }
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
