import AppKit

/// Row-level selection override so the NSTableView uses Cairn's
/// `accentMuted` pill (system accent @ 22% alpha + rounded rect) instead of
/// the default solid-accent selection. Matches the sidebar highlight and
/// SearchField border so all three interaction surfaces share one language.
///
/// `controlAccentColor` is used (not a hardcoded RGBA) so the User > System
/// Settings > Appearance > Accent Color choice propagates automatically.
final class FileListRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        let color = NSColor.controlAccentColor.withAlphaComponent(0.22)
        color.setFill()
        let rect = bounds.insetBy(dx: 2, dy: 0)
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        path.fill()
    }
}
