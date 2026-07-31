import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
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
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .disabled(model.zoomScale <= 1)
                    .accessibilityLabel("Zoom Out")
                    .help("Zoom Out (⌘−)")

                    Button {
                        model.resetZoom()
                    } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                    }
                    .disabled(model.zoomScale <= 1)
                    .accessibilityLabel("Fit to Window")
                    .help("Fit to Window (⌘0)")

                    Text(model.zoomScale <= 1.001 ? "Fit" : "\(Int((model.zoomScale * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 34)

                    Button {
                        model.zoomIn()
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .disabled(model.zoomScale >= 8)
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
            "Couldn’t Open Folder",
            isPresented: Binding(
                get: { model.loadError != nil },
                set: { if !$0 { model.loadError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.loadError ?? "")
        }
    }
}

private struct LoadingOverlay: View {
    var body: some View {
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Indexing photos")
    }
}
