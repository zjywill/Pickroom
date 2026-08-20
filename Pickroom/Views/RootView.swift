import AppKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 204, ideal: 228, max: 272)
        } content: {
            Group {
                if model.assets.isEmpty {
                    EmptyLibraryView()
                } else if model.filteredAssets.isEmpty {
                    EmptyFilterView()
                } else {
                    WorkspaceView()
                }
            }
            .navigationSplitViewColumnWidth(min: 650, ideal: 900)
        } detail: {
            InspectorView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
        }
        .navigationSplitViewStyle(.balanced)
        .disabled(model.isLoading || model.isManagingRejects)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    model.openFolder()
                } label: {
                    Label("Open Folder", systemImage: "folder.badge.plus")
                }
                .help("Open Photo Folder (⌘O)")
            }

            if !model.assets.isEmpty {
                ToolbarItem(placement: .principal) {
                    Picker("Workspace", selection: Binding(
                        get: { model.workspaceMode },
                        set: { model.workspaceMode = $0 }
                    )) {
                        ForEach(WorkspaceMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.symbol)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 170)
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    if model.currentAssetNeedsDownload {
                        Button {
                            Task { await model.downloadCurrentOriginal() }
                        } label: {
                            if model.isDownloadingOriginal {
                                ProgressView(value: model.downloadProgress)
                                    .progressViewStyle(.circular)
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.down.circle")
                            }
                        }
                        .disabled(model.isDownloadingOriginal)
                        .accessibilityLabel("Download Original")
                        .help("Download the original from iCloud for 1:1 focus and capture settings (⌘D)")
                    }

                    Button {
                        model.toggleCompositionGrid()
                    } label: {
                        Image(systemName: "grid")
                            .symbolVariant(model.compositionGridEnabled ? .fill : .none)
                    }
                    .foregroundStyle(model.compositionGridEnabled ? Color.accentColor : .primary)
                    .help("Composition Grid (C)")

                    Button {
                        model.zoomOut()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(model.zoomScale <= 1)
                    .accessibilityLabel("Zoom Out")
                    .help("Zoom Out (⌘−)")

                    Menu {
                        Button("Fit to Window") {
                            model.resetZoom()
                        }
                        Button("Actual Size") {
                            model.zoomToActualSize()
                        }
                    } label: {
                        Text(model.zoomDisplayLabel)
                            .font(.caption.monospacedDigit())
                            .frame(minWidth: 38)
                    }
                    .menuIndicator(.hidden)
                    .accessibilityLabel("Zoom")
                    .help("Zoom: \(model.zoomDisplayLabel)")

                    Button {
                        model.zoomIn()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(model.zoomScale >= model.maximumZoomScale)
                    .accessibilityLabel("Zoom In")
                    .help("Zoom In (⌘+)")
                }
            }
        }
        // Hiding the toolbar material lets the sidebar and the canvas run all
        // the way to the top of the window, so there is no separate toolbar
        // band in a colour that drifts with whatever is behind the window.
        .toolbarBackground(.hidden, for: .windowToolbar)
        .overlay {
            if model.isLoading {
                LoadingOverlay()
            }
        }
        .alert(
            "No Supported Photos",
            isPresented: Binding(
                get: { model.loadError != nil },
                set: { if !$0 { model.loadError = nil } }
            )
        ) {
            if !model.isPhotosSource {
                Button("Choose Another Folder") {
                    model.openFolder()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.loadError ?? "")
        }
        .alert(
            "Photo Library Unavailable",
            isPresented: Binding(
                get: { model.photoLibraryError != nil },
                set: { if !$0 { model.photoLibraryError = nil } }
            )
        ) {
            if model.photoAccess == .denied {
                Button("Open Privacy Settings") {
                    let url = URL(
                        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos"
                    )
                    if let url {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.photoLibraryError ?? "")
        }
        .alert(
            "Couldn’t Complete File Operation",
            isPresented: Binding(
                get: { model.fileOperationError != nil },
                set: { if !$0 { model.fileOperationError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.fileOperationError ?? "")
        }
        .alert(
            model.trashConfirmationTitle,
            isPresented: Binding(
                get: { model.isShowingTrashConfirmation },
                set: { model.isShowingTrashConfirmation = $0 }
            )
        ) {
            Button("Cancel", role: .cancel) {}
            Button(
                model.isPhotosSource ? "Delete Photos" : "Move to Trash",
                role: .destructive
            ) {
                Task {
                    await model.moveRejectedPhotosToTrash()
                }
            }
        } message: {
            Text(model.trashConfirmationMessage)
        }
    }
}

private struct LoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.14)

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Indexing photos…")
                    .font(.headline)
                Text("Reading previews and capture data")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Indexing photos")
        }
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
