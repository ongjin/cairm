import AppKit
import QuickLookUI

/// NSTableView subclass that surfaces ⏎/Enter (activation), right-click (menu),
/// and Space (Quick Look) as events the Coordinator can handle. Also participates
/// in the QLPreviewPanel responder-chain protocol so Space opens a preview of the
/// selected files.
final class FileListNSTableView: NSTableView {
    /// Fired on ⏎ / numpad-Enter.
    var activationHandler: (() -> Void)?

    /// Returned by AppKit when the user right-clicks.
    var menuHandler: ((NSEvent) -> NSMenu?)?

    /// Sets the panel's dataSource/delegate when Quick Look takes control. The
    /// Coordinator is the actual QL delegate — it owns the snapshot + selection
    /// state needed to answer QL's queries.
    weak var quickLookDelegate: (NSObject & QLPreviewPanelDataSource & QLPreviewPanelDelegate)?

    override func keyDown(with event: NSEvent) {
        // 36 = Return (main kb), 76 = numpad Enter, 49 = Space.
        switch event.keyCode {
        case 36, 76:
            activationHandler?()
        case 49:
            if let panel = QLPreviewPanel.shared() {
                panel.makeKeyAndOrderFront(nil)
            }
        default:
            super.keyDown(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        if let handler = menuHandler {
            return handler(event)
        }
        return super.menu(for: event)
    }

    // MARK: - QLPreviewPanel responder-chain hooks

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = quickLookDelegate
        panel.delegate = quickLookDelegate
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }
}
