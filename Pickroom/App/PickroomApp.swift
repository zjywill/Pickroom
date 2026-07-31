import SwiftUI

@main
struct PickroomApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .frame(minWidth: 1_080, minHeight: 700)
                .task {
                    await model.restoreLastFolderIfAvailable()
                }
        }
        .defaultSize(width: 1_440, height: 900)
        .commands {
            PickroomCommands(model: model)
        }
    }
}
