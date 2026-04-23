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
    /// The directory `load(_:)` most recently loaded. Consumers (e.g. the
    /// paste handler) use this as the destination for new-file operations.
    /// nil before the first load.
    private(set) var currentFolder: URL?

    private(set) var currentPath: FSPath?

    private let engine: CairnEngine

    /// Memoized result of the last `sortedEntries` access. Invalidated to nil
    /// every time `entries` or `sortDescriptor` mutates. The 10K-entry sort is
    /// O(N log N) and was previously re-run on every selection change /
    /// snapshot apply (multiple times per gesture). Caching collapses those
    /// to a single sort per data change.
    private var _sortedCache: [FileEntry]?

    init(engine: CairnEngine) {
        self.engine = engine
    }

    /// Test/internal entry-point — bypasses the engine and lets unit tests
    /// inject a known fixture. Production code uses `load(_:)`.
    func setEntries(_ list: [FileEntry]) {
        entries = list
        _sortedCache = nil
        state = .loaded
    }

    /// Loads the folder via an abstract FSPath + provider. This is the canonical
    /// entry point. Keeps `currentFolder` in sync for local paths so
    /// callers that depend on the URL compatibility facade keep working.
    @MainActor
    func load(_ path: FSPath, via provider: FileSystemProvider) async {
        state = .loading
        currentPath = path
        if case .local = path.provider {
            currentFolder = URL(fileURLWithPath: path.path)
        }
        do {
            let list = try await provider.list(path)
            entries = list
            _sortedCache = nil
            state = .loaded
        } catch {
            entries = []
            _sortedCache = nil
            state = .failed(ErrorMessage.userFacing(error))
        }
    }

    /// Loads the folder. Caller must ensure security-scoped access is active.
    /// Thin adapter over `load(_:via:)` — kept for call-sites that already hold a URL.
    @MainActor
    func load(_ url: URL) async {
        let p = FSPath(provider: .local, path: url.path)
        await load(p, via: LocalFileSystemProvider(engine: engine))
    }

    func clear() {
        entries = []
        _sortedCache = nil
        selection = []
        state = .idle
        currentFolder = nil
        currentPath = nil
    }

    func setSortDescriptor(_ desc: SortDescriptor) {
        guard sortDescriptor != desc else { return }
        sortDescriptor = desc
        _sortedCache = nil
    }

    func setSelection(_ paths: Set<String>) {
        selection = paths
    }

    /// Computed view: entries with directories first, then the chosen sort
    /// field applied within each group. Cached — see `_sortedCache`. Cache
    /// is invalidated on any mutation of `entries` or `sortDescriptor`.
    ///
    /// The name sort uses a "decorate-sort-undecorate" pass that lowercases
    /// each name once into a key array, instead of lowercasing both sides on
    /// every comparison. For 10K entries that's ~10K allocations instead of
    /// ~260K. Other sort fields (size, modified) compare cheap scalars and
    /// use the shared comparator unchanged.
    var sortedEntries: [FileEntry] {
        if let cached = _sortedCache { return cached }
        let sorted: [FileEntry]
        if sortDescriptor.field == .name {
            sorted = Self.sortedByName(entries, order: sortDescriptor.order)
        } else {
            sorted = entries.sorted(by: Self.comparator(for: sortDescriptor))
        }
        _sortedCache = sorted
        return sorted
    }
}
