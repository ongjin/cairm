import AppKit

/// NSTableView subclass that surfaces ⏎ / numpad-Enter as an activation event.
/// Default NSTableView passes those keys through to the responder chain, which
/// is what we want to *override* — Cairn treats Return on a selected row as
/// "open this entry" (folder enter or file open).
final class FileListNSTableView: NSTableView {
    /// Set by FileListView.makeNSView right after construction. Optional because
    /// the table briefly exists before the Coordinator attaches.
    var activationHandler: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // 36 = Return (main keyboard), 76 = numpad Enter.
        if event.keyCode == 36 || event.keyCode == 76 {
            activationHandler?()
            return
        }
        super.keyDown(with: event)
    }
}
