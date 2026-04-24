import AppKit

/// Installed as the app's `NSServicesProvider`. AppKit dispatches
/// `openInCairn(_:userData:error:)` when the user picks "Open in Cairn"
/// from Finder's Services submenu.
@MainActor
final class CairnServicesProvider: NSObject {
    static let shared = CairnServicesProvider()
    weak var app: AppModel?

    @objc func openInCairn(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls: [URL]
        if let fileURLs = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            urls = fileURLs
        } else if let fileURLs = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [NSURL] {
            urls = fileURLs.map { $0 as URL }
        } else if let names = pboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
            urls = names.map { URL(fileURLWithPath: $0) }
        } else if let names = pboard.propertyList(forType: .fileURL) as? [String] {
            urls = names.compactMap { URL(string: $0) }
        } else if let text = pboard.string(forType: .string) {
            urls = text.split(whereSeparator: \.isNewline).map { URL(fileURLWithPath: String($0)) }
        } else {
            error.pointee = "No file URLs on pasteboard" as NSString
            return
        }
        guard let app = app, let scene = app.activeScene else {
            error.pointee = "Cairn is not ready" as NSString
            return
        }
        for url in urls {
            CairnURLRouter.dispatch(.openLocal(url), in: app, activeScene: scene)
        }
    }
}
