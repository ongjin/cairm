import Foundation

/// Remembers the last folder the user was viewing so we can restore it on next
/// launch. Stored as a POSIX path string in UserDefaults — simple and doesn't
/// require an active bookmark (the bookmark layer is a separate concern).
///
/// `load()` defensively returns nil if the stored path no longer exists on disk,
/// letting AppModel fall back to Home without surfacing a stale error.
struct LastFolderStore {
    private let defaults: UserDefaults
    private let key = "cairn.lastFolderPath"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(_ url: URL) {
        defaults.set(url.standardizedFileURL.path, forKey: key)
    }

    func load() -> URL? {
        guard let path = defaults.string(forKey: key) else { return nil }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
