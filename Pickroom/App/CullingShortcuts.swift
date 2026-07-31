import AppKit
import SwiftUI

/// Single-key commands the culling workflow answers to.
enum CullingShortcut: Equatable, Sendable {
    case decision(PhotoDecision)
    case unmark
    case rating(Int)
    case actualSize
    case toggleActualSize
    case toggleCompositionGrid

    /// Maps a plain keystroke onto a command, ignoring anything pressed with a
    /// modifier so menu shortcuts such as ⌘0 keep their own meaning.
    static func command(
        key: String,
        modifiers: NSEvent.ModifierFlags = []
    ) -> CullingShortcut? {
        guard modifiers.intersection([.command, .control, .option, .function]).isEmpty else {
            return nil
        }

        switch key.lowercased() {
        case "p": return .decision(.pick)
        case "m": return .decision(.maybe)
        case "x": return .decision(.reject)
        case "u": return .unmark
        case "c": return .toggleCompositionGrid
        case "z": return .actualSize
        case " ": return .toggleActualSize
        default:
            guard let rating = Int(key), (0...5).contains(rating) else { return nil }
            return .rating(rating)
        }
    }

    @MainActor
    func apply(to model: AppModel) {
        switch self {
        case .decision(let decision): model.setDecision(decision)
        case .unmark: model.setDecision(.unreviewed, advance: false)
        case .rating(let rating): model.setRating(rating)
        case .actualSize: model.zoomToActualSize()
        case .toggleActualSize: model.toggleActualSize()
        case .toggleCompositionGrid: model.toggleCompositionGrid()
        }
    }
}

/// Delivers `CullingShortcut` keys before AppKit's responder chain sees them.
///
/// Sidebar rows use type-select, so a plain `p` or `m` selects the "Picks" or
/// "Maybes" filter and the matching menu key equivalent never fires. A local
/// event monitor runs ahead of `-[NSApplication sendEvent:]`, so the shortcuts
/// reach the model no matter which control holds focus.
@MainActor
final class CullingKeyMonitor {
    static let shared = CullingKeyMonitor()

    private var monitor: Any?
    private var activations = 0
    private weak var model: AppModel?

    private init() {}

    func activate(model: AppModel) {
        self.model = model
        activations += 1

        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard
                !event.isARepeat,
                let key = event.charactersIgnoringModifiers,
                let command = CullingShortcut.command(
                    key: key,
                    modifiers: event.modifierFlags
                )
            else {
                return event
            }

            let handled = MainActor.assumeIsolated {
                CullingKeyMonitor.shared.perform(command)
            }
            return handled ? nil : event
        }
    }

    func deactivate() {
        activations = max(activations - 1, 0)
        guard activations == 0, let monitor else { return }

        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    private func perform(_ command: CullingShortcut) -> Bool {
        guard
            let model,
            !model.isLoading,
            !model.isManagingRejects,
            NSApp.modalWindow == nil,
            NSApp.keyWindow?.isSheet != true,
            !isEditingText
        else {
            return false
        }

        command.apply(to: model)
        return true
    }

    private var isEditingText: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder as? NSText else { return false }
        return responder.isEditable
    }
}

extension View {
    func cullingKeyShortcuts(model: AppModel) -> some View {
        onAppear {
            CullingKeyMonitor.shared.activate(model: model)
        }
        .onDisappear {
            CullingKeyMonitor.shared.deactivate()
        }
    }
}
