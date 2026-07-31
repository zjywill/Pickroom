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
            !isLoading,
            let currentAssetID,
            let index = assets.firstIndex(where: { $0.id == currentAssetID })
        else {
            return
        }

        assets[index].rating = min(max(rating, 0), 5)
        persistSelection(for: assets[index])
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
