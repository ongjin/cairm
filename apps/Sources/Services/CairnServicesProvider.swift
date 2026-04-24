import AppKit

/// Installed as the app's `NSServicesProvider`. AppKit dispatches
/// `openInCairn(_:userData:error:)` when the user picks "Open in Cairn"
/// from Finder's Services submenu.
@MainActor
final class CairnServicesProvider: NSObject {
    static let shared = CairnServicesProvider()
    weak var app: AppModel?

    @objc func openInCairn(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = Self.urls(from: pboard)
        guard !urls.isEmpty else {
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

    private static func urls(from pboard: NSPasteboard) -> [URL] {
        if let fileURLs = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !fileURLs.isEmpty {
            return fileURLs
        }
        if let fileURLs = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [NSURL], !fileURLs.isEmpty {
            return fileURLs.map { $0 as URL }
        }
        if let names = pboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String], !names.isEmpty {
            return names.map { URL(fileURLWithPath: $0) }
        }
        if let names = pboard.propertyList(forType: .fileURL) as? [String], !names.isEmpty {
            return names.compactMap(fileURL(fromPasteboardString:))
        }
        if let name = pboard.string(forType: .fileURL), let url = fileURL(fromPasteboardString: name) {
            return [url]
        }
        if let text = pboard.string(forType: .string) {
            return text.split(whereSeparator: \.isNewline)
                .compactMap { fileURL(fromPasteboardString: String($0)) }
        }
        return []
    }

    private static func fileURL(fromPasteboardString value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.isFileURL {
            return url
        }
        return URL(fileURLWithPath: trimmed)
    }
}
