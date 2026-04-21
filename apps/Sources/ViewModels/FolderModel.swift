import Foundation
import Observation

/// Folder-scoped view model. One instance per currently-displayed folder.
///
/// Owns:
///   - `entries`  — raw output of the engine (Rust default order).
///   - `sortDescriptor` — user-driven Name/Size/Modified × asc/desc.
///   - `sortedEntries` — derived view (recomputed from entries + sortDescriptor).
///   - `selection` — set of FileEntry paths currently highlighted in the table.
///
/// Sort policy: directories always come first regardless of sort field, then
/// the chosen field within each group. Matches Finder convention and gives
/// stable behaviour when toggling sort columns.
@Observable
final class FolderModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    enum SortField: String, Equatable {
        case name
        case size
        case modified
    }

    enum SortOrder: Equatable {
        case ascending
        case descending
    }

    struct SortDescriptor: Equatable {
        var field: SortField
        var order: SortOrder

        static let `default` = SortDescriptor(field: .name, order: .ascending)
    }

    private(set) var entries: [FileEntry] = []
    private(set) var state: LoadState = .idle
    private(set) var sortDescriptor: SortDescriptor = .default
    /// Path strings of currently-selected entries.
    private(set) var selection: Set<String> = []

    private let engine: CairnEngine

    init(engine: CairnEngine) {
        self.engine = engine
    }

    /// Test/internal entry-point — bypasses the engine and lets unit tests
    /// inject a known fixture. Production code uses `load(_:)`.
    func setEntries(_ list: [FileEntry]) {
        entries = list
        state = .loaded
    }

    /// Loads the folder. Caller must ensure security-scoped access is active.
    @MainActor
    func load(_ url: URL) async {
        state = .loading
        do {
            let list = try await engine.listDirectory(url)
            entries = list
            state = .loaded
        } catch {
            entries = []
            state = .failed(String(describing: error))
        }
    }

    func clear() {
        entries = []
        selection = []
        state = .idle
    }

    func setSortDescriptor(_ desc: SortDescriptor) {
        sortDescriptor = desc
    }

    func setSelection(_ paths: Set<String>) {
        selection = paths
    }

    /// Computed view: entries with directories first, then the chosen sort
    /// field applied within each group. Recomputed every access — fine for the
    /// 10K-entry ceiling. Phase 2 should cache if it ever shows up in profiles.
    var sortedEntries: [FileEntry] {
        let dirs = entries.filter { $0.kind == .Directory }
        let files = entries.filter { $0.kind != .Directory }
        return Self.sort(dirs, by: sortDescriptor) + Self.sort(files, by: sortDescriptor)
    }

    private static func sort(_ list: [FileEntry], by desc: SortDescriptor) -> [FileEntry] {
        let asc = (desc.order == .ascending)
        switch desc.field {
        case .name:
            return list.sorted { lhs, rhs in
                let l = lhs.name.toString().lowercased()
                let r = rhs.name.toString().lowercased()
                return asc ? (l < r) : (l > r)
            }
        case .size:
            return list.sorted { lhs, rhs in
                asc ? (lhs.size < rhs.size) : (lhs.size > rhs.size)
            }
        case .modified:
            return list.sorted { lhs, rhs in
                asc ? (lhs.modified_unix < rhs.modified_unix)
                    : (lhs.modified_unix > rhs.modified_unix)
            }
        }
    }
}
