import AppKit

/// NSTableView subclass that surfaces ⏎ / numpad-Enter as an activation event
/// and right-click as a context-menu event. Both are delegated out via closures
/// that the Coordinator attaches in FileListView.makeNSView.
final class FileListNSTableView: NSTableView {
    /// Fired on ⏎ / numpad-Enter when a row is selected.
    var activationHandler: (() -> Void)?

    /// Called by AppKit when the user right-clicks. Returning nil means no menu.
    /// The closure receives the originating event so the Coordinator can map
    /// window-coordinates to a specific row.
    var menuHandler: ((NSEvent) -> NSMenu?)?

    override func keyDown(with event: NSEvent) {
        // 36 = Return (main keyboard), 76 = numpad Enter.
        if event.keyCode == 36 || event.keyCode == 76 {
            activationHandler?()
            return
        }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        if let handler = menuHandler {
            return handler(event)
        }
        return super.menu(for: event)
    }
}
