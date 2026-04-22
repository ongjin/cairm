import AppKit
import QuickLookUI

/// NSTableView subclass that surfaces ⏎/Enter (activation), right-click (menu),
/// and Space (Quick Look) as events the Coordinator can handle. Also participates
/// in the QLPreviewPanel responder-chain protocol so Space opens a preview of the
/// selected files, and implements Finder-style marquee (rubber-band) selection
/// when the user drags from empty space.
final class FileListNSTableView: NSTableView {
    /// Fired on ⏎ / numpad-Enter.
    var activationHandler: (() -> Void)?

    /// Fired on ⌘⌫ — Finder's "Move to Trash" shortcut. Coordinator owns the
    /// trash logic so it can iterate over the model's selected indexes
    /// without the subclass needing a back-pointer to FolderModel.
    var deleteHandler: (() -> Void)?

    /// Fired on ⌘C — copy selected rows' URLs to the general pasteboard.
    var copyHandler: (() -> Void)?

    /// Fired on ⌘V (.copy) or ⌥⌘V (.move).
    var pasteHandler: ((PasteOp) -> Void)?

    /// Returned by AppKit when the user right-clicks.
    var menuHandler: ((NSEvent) -> NSMenu?)?

    /// Sets the panel's dataSource/delegate when Quick Look takes control. The
    /// Coordinator is the actual QL delegate — it owns the snapshot + selection
    /// state needed to answer QL's queries.
    weak var quickLookDelegate: (NSObject & QLPreviewPanelDataSource & QLPreviewPanelDelegate)?

    private var marqueeOverlay: MarqueeOverlay?

    override func keyDown(with event: NSEvent) {
        // 36 = Return, 76 = numpad Enter, 49 = Space, 51 = Delete (backspace).
        switch event.keyCode {
        case 36, 76:
            activationHandler?()
        case 49:
            if let panel = QLPreviewPanel.shared() {
                panel.makeKeyAndOrderFront(nil)
            }
        case 51 where event.modifierFlags.contains(.command):
            // ⌘⌫ — match Finder. Plain ⌫ is intentionally a no-op (saves
            // novice users from a panic-delete).
            deleteHandler?()
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

    // MARK: - Standard Cocoa edit actions

    // @objc (not override): NSResponder.copy(_:) isn't exposed as overridable
    // in Swift due to NSCopying.copy() name collision. Cocoa still dispatches
    // to this method by selector — that's what matters.
    @objc func copy(_ sender: Any?) {
        copyHandler?()
    }

    // @objc (not override): NSResponder.paste(_:) isn't exposed as overridable
    // in Swift (same SDK limitation as copy(_:)). Selector dispatch still works.
    @objc func paste(_ sender: Any?) {
        pasteHandler?(.copy)
    }

    // Custom selector, declared on CairnResponder. NSMenuItem in the Edit menu
    // uses this selector, and the responder chain finds us because we're the
    // window's first responder when the table is focused.
    @objc func pasteItemHere(_ sender: Any?) {
        pasteHandler?(.move)
    }

    // @objc (not override): NSTableView doesn't surface validateMenuItem(_:) as
    // overridable in Swift — NSMenuItemValidation is adopted at the ObjC level.
    // Selector dispatch still works. Default branch returns true (can't call
    // super.validateMenuItem here since Swift doesn't see the method on the
    // superclass).
    @objc func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(copy(_:)):
            return !selectedRowIndexes.isEmpty
        case #selector(paste(_:)), #selector(pasteItemHere(_:)):
            return ClipboardPasteService.read(from: .general) != nil
        default:
            return true
        }
    }

    // MARK: - Marquee selection
    //
    // NSTableView's `.inset` style does not draw a rubber-band when the user
    // drags in empty space, so we implement it here. When mouseDown lands on
    // an actual row we fall through to the default behavior (so single-row
    // click + ⌘/⇧ extension keep working). When it lands in empty space, we
    // run a tracking loop that updates row selection from the rect's
    // intersection with `rows(in:)` and draws a translucent overlay so the
    // user can see what they're enclosing.

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: local)

        if clickedRow >= 0 {
            super.mouseDown(with: event)
            return
        }

        let extending = event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.command)
        let baseSelection: IndexSet = extending ? selectedRowIndexes : IndexSet()
        if !extending && !selectedRowIndexes.isEmpty {
            deselectAll(nil)
        }

        let overlay = MarqueeOverlay(frame: .zero)
        addSubview(overlay)
        marqueeOverlay = overlay

        let start = local
        var lastApplied = baseSelection

        defer {
            overlay.removeFromSuperview()
            marqueeOverlay = nil
        }

        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let p = convert(next.locationInWindow, from: nil)
            let rect = NSRect(
                x: min(start.x, p.x),
                y: min(start.y, p.y),
                width: abs(p.x - start.x),
                height: abs(p.y - start.y)
            )
            overlay.frame = rect
            overlay.needsDisplay = true

            // rows(in:) returns NSRange of rows whose frame intersects the rect.
            let range = rows(in: rect)
            var picked = baseSelection
            if range.length > 0 {
                for r in range.location..<(range.location + range.length) {
                    picked.insert(r)
                }
            }
            if picked != lastApplied {
                selectRowIndexes(picked, byExtendingSelection: false)
                lastApplied = picked
            }

            // Auto-scroll when dragging near the edge.
            autoscroll(with: next)

            if next.type == .leftMouseUp { break }
        }
    }

    // MARK: - QLPreviewPanel responder-chain hooks

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        // Freeze the selection snapshot so panel navigation isn't destabilized
        // by live row-selection changes happening beneath the open panel.
        (quickLookDelegate as? FileListCoordinator)?.snapshotQuickLookURLs()
        panel.dataSource = quickLookDelegate
        panel.delegate = quickLookDelegate
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
        (quickLookDelegate as? FileListCoordinator)?.clearQuickLookSnapshot()
    }
}

/// Translucent rectangle drawn on top of FileListNSTableView during a marquee
/// drag. Uses the system control accent for tint so it matches the row
/// selection color.
private final class MarqueeOverlay: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor.controlAccentColor
        accent.withAlphaComponent(0.18).setFill()
        bounds.fill()
        accent.withAlphaComponent(0.55).setStroke()
        let path = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        path.lineWidth = 1
        path.stroke()
    }
}
