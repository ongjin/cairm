import Foundation
import Observation

/// Kind of a bookmark — determines which list it lives in.
enum BookmarkKind: String, Codable {
    case pinned
    case recent
}

/// A persisted handle to a user-selected folder. Stored as security-scoped
/// bookmark data so access survives app restarts under App Sandbox.
struct BookmarkEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let bookmarkData: Data
    var lastKnownPath: String
    let addedAt: Date
    var label: String?
    let kind: BookmarkKind
}

/// Persistence-backed store of security-scoped bookmarks.
///
/// Phase 1 scope:
///   - `register(url, kind)` — create + persist.
///   - `resolve(entry)` — turn stored bookmark back into a URL.
///   - `startAccessing` / `stopAccessing` with reference counting per bookmark.
///   - Persistence in JSON files inside `storageDirectory` (default: App Support).
///   - Recent list is LRU-capped at 20 with path-standardized dedup.
///
/// Intentionally NOT in Phase 1: stale-bookmark re-prompt UI (Phase 2), drag to reorder (Phase 2).
@Observable
final class BookmarkStore {
    private(set) var pinned: [BookmarkEntry] = []
    private(set) var recent: [BookmarkEntry] = []

    private let storageDirectory: URL
    private var activeCounts: [UUID: Int] = [:]

    static let recentCap = 20

    /// - Parameter storageDirectory: Directory used to persist JSON files.
    ///   Tests pass a tempdir; app code passes App Support.
    init(storageDirectory: URL) {
        self.storageDirectory = storageDirectory
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        loadAll()
    }

    /// Convenience init that uses `Library/Application Support/Cairn` inside the sandbox container.
    convenience init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        self.init(storageDirectory: appSupport.appendingPathComponent("Cairn"))
    }

    // MARK: - Registration

    /// Create a security-scoped bookmark for `url`, persist it, and return the entry.
    /// Path comparison for dedup uses `url.standardizedFileURL.path`.
    @discardableResult
    func register(_ url: URL, kind: BookmarkKind) throws -> BookmarkEntry {
        let standardized = url.standardizedFileURL
        let data = try standardized.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let entry = BookmarkEntry(
            id: UUID(),
            bookmarkData: data,
            lastKnownPath: standardized.path,
            addedAt: Date(),
            label: nil,
            kind: kind
        )

        switch kind {
        case .pinned:
            // Pinned dedup: don't add if the same path is already pinned.
            if !pinned.contains(where: { $0.lastKnownPath == entry.lastKnownPath }) {
                pinned.append(entry)
                save(kind: .pinned)
            }
        case .recent:
            // Recent: move-to-front dedup by path; cap at 20.
            recent.removeAll { $0.lastKnownPath == entry.lastKnownPath }
            recent.insert(entry, at: 0)
            if recent.count > Self.recentCap {
                recent = Array(recent.prefix(Self.recentCap))
            }
            save(kind: .recent)
        }
        return entry
    }

    func unpin(_ entry: BookmarkEntry) {
        pinned.removeAll { $0.id == entry.id }
        save(kind: .pinned)
    }

    // MARK: - Resolution & access

    /// Returns the URL if the bookmark resolves cleanly. Returns nil if stale.
    func resolve(_ entry: BookmarkEntry) -> URL? {
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: entry.bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        if stale { return nil }
        return url
    }

    /// Increments ref count and calls `startAccessingSecurityScopedResource()`
    /// only on first use for that bookmark in this session.
    func startAccessing(_ entry: BookmarkEntry) -> URL? {
        guard let url = resolve(entry) else { return nil }
        let count = (activeCounts[entry.id] ?? 0) + 1
        activeCounts[entry.id] = count
        if count == 1 {
            _ = url.startAccessingSecurityScopedResource()
        }
        return url
    }

    /// Decrements ref count and calls `stopAccessingSecurityScopedResource()`
    /// only when the count drops to zero.
    func stopAccessing(_ entry: BookmarkEntry) {
        guard let count = activeCounts[entry.id], count > 0 else { return }
        let next = count - 1
        if next == 0 {
            activeCounts.removeValue(forKey: entry.id)
            if let url = resolve(entry) {
                url.stopAccessingSecurityScopedResource()
            }
        } else {
            activeCounts[entry.id] = next
        }
    }

    // MARK: - Persistence

    private func fileURL(for kind: BookmarkKind) -> URL {
        storageDirectory.appendingPathComponent("\(kind.rawValue).json")
    }

    private func save(kind: BookmarkKind) {
        let list: [BookmarkEntry] = (kind == .pinned) ? pinned : recent
        do {
            let data = try JSONEncoder().encode(list)
            try data.write(to: fileURL(for: kind), options: [.atomic])
        } catch {
            // Phase 1: tolerate persistence failures silently. Phase 2 logs/report.
        }
    }

    private func loadAll() {
        pinned = load(.pinned)
        recent = load(.recent)
    }

    private func load(_ kind: BookmarkKind) -> [BookmarkEntry] {
        let url = fileURL(for: kind)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([BookmarkEntry].self, from: data)
        else { return [] }
        return decoded
    }
}
