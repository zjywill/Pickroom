import SwiftUI

struct WorkspaceView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.workspaceMode {
            case .cull:
                CullWorkspaceView()
            case .grid:
                PhotoGridView()
            }
        }
        .navigationTitle(model.sourceName)
    }
}

private struct CullWorkspaceView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            if let asset = model.currentAsset {
                PhotoCanvas(asset: asset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                CaptureStrip(asset: asset)
                FilmstripView()
                DecisionBar()
            }
        }
        .background(PickroomColors.canvas)
    }
}
