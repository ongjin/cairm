import AppKit
import Foundation

/// Extension-keyed cache over `NSWorkspace.shared.icon(forFile:)`.
///
/// Rationale: `icon(forFile:)` returns the same visual icon for all files
/// sharing an extension (e.g., every `.swift` file gets the same "Swift
/// source" badge). Keying the cache by lowercased extension avoids a
/// per-path fetch and a per-row NSImage allocation — a noticeable saving in
/// large directories (1K+ files).
///
/// The cache persists for the app lifetime. Directories use a fixed sentinel
/// key because the system Folder icon is uniform.
final class FileListIconCache {
    private let cache = NSCache<NSString, NSImage>()
    private static let directoryKey: NSString = "__directory__"

    init() {
        cache.countLimit = 500  // 전형적 세션의 ext 다양성은 50 미만, 500 은 여유
    }

    /// Returns the cached icon for `path`. On miss, calls
    /// `NSWorkspace.shared.icon(forFile:)` and stores it.
    func icon(forPath path: String, isDirectory: Bool) -> NSImage {
        let key: NSString
        if isDirectory {
            key = Self.directoryKey
        } else {
            key = NSString(string: (path as NSString).pathExtension.lowercased())
        }
        if let hit = cache.object(forKey: key) {
            return hit
        }
        let img = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(img, forKey: key)
        return img
    }
}
