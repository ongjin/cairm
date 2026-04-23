import SwiftUI
import AppKit

/// Publishes its host NSWindow through a @Binding. Drop into a
/// `.background(WindowAccessor(window: $hostWindow))` to capture the
/// containing window from a SwiftUI view — useful for any AppKit
/// bridging that needs to disambiguate multi-window state
/// (event monitors, global hotkey targets, NSPanel anchoring).
///
/// The window isn't known until the view is attached to the window
/// hierarchy, so the representable sets it asynchronously on
/// `makeNSView` and whenever `viewDidMoveToWindow` fires.
struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = TrackerView()
        view.onWindowChange = { self.window = $0 }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class TrackerView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange?(window)
        }
    }
}
