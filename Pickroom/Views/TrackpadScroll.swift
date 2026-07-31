import AppKit
import SwiftUI

/// One trackpad or mouse scroll event, reduced to what the canvas needs.
struct ScrollSample: Equatable, Sendable {
    var deltaX: CGFloat
    var deltaY: CGFloat
}

/// Receives scroll events for the canvas without taking its mouse gestures.
struct TrackpadScrollCatcher: NSViewRepresentable {
    let onScroll: (ScrollSample) -> Void

    func makeNSView(context: Context) -> ScrollCatcherView {
        let view = ScrollCatcherView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollCatcherView, context: Context) {
        nsView.onScroll = onScroll
    }
}

final class ScrollCatcherView: NSView {
    var onScroll: ((ScrollSample) -> Void)?

    /// Claims scroll events only. Clicks, drags, and pinches fall through to
    /// the SwiftUI gestures underneath.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard NSApp.currentEvent?.type == .scrollWheel else { return nil }
        return super.hitTest(point)
    }

    override func scrollWheel(with event: NSEvent) {
        onScroll?(
            ScrollSample(
                deltaX: event.scrollingDeltaX,
                deltaY: event.scrollingDeltaY
            )
        )
    }
}
