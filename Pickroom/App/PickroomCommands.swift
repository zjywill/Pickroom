import SwiftUI

struct PickroomCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Photo Folder…") {
                model.openFolder()
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(model.isLoading)
        }

        CommandMenu("Photo") {
            Button("Previous Photo") {
                model.selectPrevious()
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            .disabled(model.currentAsset == nil || model.isLoading)

            Button("Next Photo") {
                model.selectNext()
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .disabled(model.currentAsset == nil || model.isLoading)

            Divider()

            Button("Pick") {
                model.setDecision(.pick)
            }
            .keyboardShortcut("p", modifiers: [])
            .disabled(model.currentAsset == nil || model.isLoading)

            Button("Maybe") {
                model.setDecision(.maybe)
            }
            .keyboardShortcut("m", modifiers: [])
            .disabled(model.currentAsset == nil || model.isLoading)

            Button("Reject") {
                model.setDecision(.reject)
            }
            .keyboardShortcut("x", modifiers: [])
            .disabled(model.currentAsset == nil || model.isLoading)

            Button("Unmark") {
                model.setDecision(.unreviewed, advance: false)
            }
            .keyboardShortcut("u", modifiers: [])
            .disabled(model.currentAsset == nil || model.isLoading)

            Divider()

            ForEach(0...5, id: \.self) { rating in
                Button(rating == 0 ? "Clear Rating" : "\(rating) Star\(rating == 1 ? "" : "s")") {
                    model.setRating(rating)
                }
                .keyboardShortcut(KeyEquivalent(Character(String(rating))), modifiers: [])
                .disabled(model.currentAsset == nil || model.isLoading)
            }
        }

        CommandMenu("Inspect") {
            Button("Culling View") {
                model.workspaceMode = .cull
            }
            .keyboardShortcut("1", modifiers: .command)
            .disabled(model.isLoading)

            Button("Contact Sheet") {
                model.workspaceMode = .grid
            }
            .keyboardShortcut("2", modifiers: .command)
            .disabled(model.isLoading)

            Divider()

            Toggle("Composition Grid", isOn: Binding(
                get: { model.compositionGridEnabled },
                set: { model.compositionGridEnabled = $0 }
            ))
            .keyboardShortcut("c", modifiers: [])
            .disabled(model.isLoading)

            Divider()

            Button("Zoom In") {
                model.zoomIn()
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(model.currentAsset == nil || model.isLoading)

            Button("Zoom Out") {
                model.zoomOut()
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(model.currentAsset == nil || model.isLoading)

            Button("Fit to Window") {
                model.resetZoom()
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(model.currentAsset == nil || model.isLoading)

            Button("Actual Size") {
                model.zoomToActualSize()
            }
            .keyboardShortcut("z", modifiers: [])
            .disabled(model.currentAsset == nil || model.isLoading)

            Button("Toggle Actual Size") {
                model.toggleActualSize()
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(model.currentAsset == nil || model.isLoading)
        }
    }
}
