import SwiftUI

@main
struct PickroomApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .cullingKeyShortcuts(model: model)
                .frame(minWidth: 1_120, minHeight: 700)
                .task {
                    await model.restoreLastFolderIfAvailable()
                }
        }
        .defaultSize(width: 1_440, height: 900)
        .windowResizability(.contentMinSize)
        .commands {
            PickroomCommands(model: model)
        }

        Window("Acknowledgements", id: AcknowledgementsWindow.id) {
            AcknowledgementsView()
        }
        .windowResizability(.contentSize)
    }
}

enum AcknowledgementsWindow {
    static let id = "acknowledgements"
}
