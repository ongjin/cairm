import AppKit
import Foundation
import UniformTypeIdentifiers

/// Extension-keyed cache over `NSWorkspace.shared.icon(for: UTType)`.
///
/// Rationale: `icon(forFile:)` only returns a meaningful icon when the path
/// exists on disk — it silently degrades to a generic document for anything
/// else (remote SFTP paths, deleted files, paths resolved before mount).
/// `icon(for: UTType)` resolves the icon purely from the declared type, which
/// makes it work uniformly for local and remote file lists.
///
/// Keying by lowercased extension collapses per-file lookups: every `.swift`
/// row shares one NSImage. Directories use a fixed sentinel key because the
/// system Folder icon is uniform.
final class FileListIconCache {
    private let cache = NSCache<NSString, NSImage>()
    private static let directoryKey: NSString = "__directory__"
    private static let extensionlessKey: NSString = "__noext__"

    init() {
        cache.countLimit = 500  // 전형적 세션의 ext 다양성은 50 미만, 500 은 여유
    }

    /// Returns the cached icon for `path`. On miss, resolves via `UTType` so
    /// the result is identical for local and SFTP-remote entries.
    func icon(forPath path: String, isDirectory: Bool) -> NSImage {
        if isDirectory {
            if let hit = cache.object(forKey: Self.directoryKey) { return hit }
            let img = NSWorkspace.shared.icon(for: .folder)
            cache.setObject(img, forKey: Self.directoryKey)
            return img
        }
        let ext = (path as NSString).pathExtension.lowercased()
        let key: NSString = ext.isEmpty ? Self.extensionlessKey : NSString(string: ext)
        if let hit = cache.object(forKey: key) { return hit }
        let type = ext.isEmpty ? UTType.data : (UTType(filenameExtension: ext) ?? .data)
        let img = NSWorkspace.shared.icon(for: type)
        cache.setObject(img, forKey: key)
        return img
    }
}
