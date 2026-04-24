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
    var scope: Scope = .subtree
    private(set) var results: [FileEntry] = []
    private(set) var phase: Phase = .idle
    private(set) var hitCount: Int = 0

    /// Live handle for the Rust walker session; `nil` when no subtree search
    /// is in flight. Exposed for the Task 9 async loop to check — Task 8 never
    /// sets a non-nil value.
    private(set) var activeHandle: UInt64?

    private var task: Task<Void, Never>?
    private var remoteCancel: CancelToken?
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
        root: FSPath?,
        provider: FileSystemProvider,
        showHidden: Bool,
        sort: FolderModel.SortDescriptor,
        folderEntries: [FileEntry]
    ) {
        task?.cancel()
        task = nil
        remoteCancel?.cancel()
        remoteCancel = nil
        if let h = activeHandle {
            engine.cancelSearch(handle: h)
            activeHandle = nil
        }

        guard !query.isEmpty, let root else {
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

        if case .ssh = provider.identifier {
            runRemoteSubtree(root: root, provider: provider, showHidden: showHidden, sort: sort)
            return
        }

        // Subtree mode — 200ms debounce, async walker, running-sort per batch.
        phase = .running
        hitCount = 0
        results = []
        let q = query
        let rootPath = root.path
        let hidden = showHidden
        let cmp = FolderModel.comparator(for: sort)
        let eng = engine

        task = Task { [weak self] in
            // Debounce — cancellation during the sleep drops this whole task.
            try? await Task.sleep(nanoseconds: 200_000_000)
            if Task.isCancelled { return }

            let handle = await eng.startSearch(
                root: rootPath, query: q, subtree: true, showHidden: hidden)
            await MainActor.run { self?.activeHandle = handle }

            // Append batches in walker order during streaming; defer the full
            // sort until the walker signals .done (or .capped). Previously we
            // re-sorted the entire results array on every batch — for 1000
            // hits across 20 batches that was 20× full sorts (~O(N² log N)
            // total). Streaming-order display is acceptable UX: results visibly
            // "stream in" and snap into final order once the walk completes.
            while !Task.isCancelled {
                guard let batch = await eng.fetchSearchBatch(handle: handle) else { break }
                if batch.isEmpty { continue } // keep-alive tick
                await MainActor.run {
                    guard let self else { return }
                    self.results.append(contentsOf: batch)
                    self.hitCount = self.results.count
                    if self.results.count >= 5_000 {
                        self.phase = .capped
                    }
                }
            }

            await MainActor.run {
                guard let self else { return }
                // Final sort: one pass once the walker is done (or cancelled
                // mid-flight — sorting is cheap on cancellation too and keeps
                // the surfaced list coherent if the user re-engages).
                self.results.sort(by: cmp)
                if case .running = self.phase { self.phase = .done }
                if self.activeHandle == handle { self.activeHandle = nil }
            }
        }
    }

    private func runRemoteSubtree(
        root: FSPath,
        provider: FileSystemProvider,
        showHidden: Bool,
        sort: FolderModel.SortDescriptor
    ) {
        phase = .running
        hitCount = 0
        results = []

        let q = query
        let token = CancelToken()
        remoteCancel = token
        let cmp = FolderModel.comparator(for: sort)

        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let stream = provider.walk(
                    root: root,
                    pattern: q,
                    maxDepth: 10,
                    cap: 10_000,
                    includeHidden: showHidden,
                    cancel: token
                )
                var next: [FileEntry] = []
                for try await entry in stream {
                    if Task.isCancelled || token.isCancelled { break }
                    next.append(entry)
                    if next.count >= 200 {
                        self.results.append(contentsOf: next)
                        self.hitCount = self.results.count
                        next.removeAll(keepingCapacity: true)
                    }
                }

                if !next.isEmpty {
                    self.results.append(contentsOf: next)
                    self.hitCount = self.results.count
                }
                self.results.sort(by: cmp)
                if case .running = self.phase {
                    self.phase = .done
                }
                if self.remoteCancel === token {
                    self.remoteCancel = nil
                }
            } catch {
                if Task.isCancelled || token.isCancelled { return }
                self.phase = .failed(String(describing: error))
                if self.remoteCancel === token {
                    self.remoteCancel = nil
                }
            }
        }
    }

    /// Abort any in-flight search and drop all results. Called on Escape /
    /// query-cleared / explicit teardown.
    func cancel() {
        clear()
    }

    /// Abort any in-flight search, clear the query, and drop all results.
    /// Called when navigation changes the folder underneath the search model.
    func clear() {
        task?.cancel()
        task = nil
        remoteCancel?.cancel()
        remoteCancel = nil
        if let h = activeHandle {
            engine.cancelSearch(handle: h)
        }
        activeHandle = nil
        query = ""
        results = []
        hitCount = 0
        phase = .idle
    }
}
