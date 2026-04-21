import Foundation
import Observation

/// Search-scoped view model paired with `ContentView`. Owns the query text,
/// scope selection (folder-local filter vs. recursive subtree walk), and
/// results buffer. Subtree streaming, cancellation, and `@Observable` wiring
/// for the async walker land in Task 9; this file only implements the
/// in-memory folder-mode filter + the shared state surface.
@Observable
final class SearchModel {
    enum Scope: String, CaseIterable, Hashable {
        case folder
        case subtree
    }

    enum Phase: Equatable {
        case idle
        case running
        case capped
        case done
        case failed(String)
    }

    var query: String = ""
    var scope: Scope = .folder
    private(set) var results: [FileEntry] = []
    private(set) var phase: Phase = .idle
    private(set) var hitCount: Int = 0

    /// Live handle for the Rust walker session; `nil` when no subtree search
    /// is in flight. Exposed for the Task 9 async loop to check — Task 8 never
    /// sets a non-nil value.
    private(set) var activeHandle: UInt64?

    private var task: Task<Void, Never>?
    private let engine: CairnEngine

    init(engine: CairnEngine) {
        self.engine = engine
    }

    /// True when a query is active and the caller should display results
    /// instead of the normal folder listing.
    var isActive: Bool { !query.isEmpty }

    /// Recompute results for the current `query` + `scope` + environment.
    /// Called from `ContentView.onChange` triggers. Task 9 extends this to
    /// spawn the subtree async walker when `scope == .subtree`.
    func refresh(
        root: URL?,
        showHidden: Bool,
        sort: FolderModel.SortDescriptor,
        folderEntries: [FileEntry]
    ) {
        task?.cancel()
        task = nil
        if let h = activeHandle {
            engine.cancelSearch(handle: h)
            activeHandle = nil
        }

        guard !query.isEmpty, root != nil else {
            results = []
            hitCount = 0
            phase = .idle
            return
        }

        if scope == .folder {
            let q = query
            let filtered = folderEntries.filter {
                $0.name.toString().localizedCaseInsensitiveContains(q)
            }
            results = filtered.sorted(by: FolderModel.comparator(for: sort))
            hitCount = results.count
            phase = .done
            return
        }

        // Subtree mode wired in Task 9; for now, leave idle so the UI doesn't
        // flash a running state we can't satisfy.
        results = []
        hitCount = 0
        phase = .idle
    }

    /// Abort any in-flight search and drop all results. Called on Escape /
    /// query-cleared / explicit teardown.
    func cancel() {
        task?.cancel()
        task = nil
        if let h = activeHandle {
            engine.cancelSearch(handle: h)
        }
        activeHandle = nil
        results = []
        hitCount = 0
        phase = .idle
    }
}
