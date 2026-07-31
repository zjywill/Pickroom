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
        .disabled(model.isLoading)
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
            Button("Choose Another Folder") {
                model.openFolder()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.loadError ?? "")
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
