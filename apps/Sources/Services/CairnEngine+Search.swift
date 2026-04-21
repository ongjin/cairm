import Foundation

/// Async-friendly Swift wrappers around the swift-bridge search FFI.
/// All calls go through `Task.detached` so the main actor never blocks on
/// the FFI boundary (`searchNextBatch` in particular blocks up to ~100ms
/// waiting on the walker's channel).
extension CairnEngine {
    /// Spawns a background search session. Returns the opaque handle used by
    /// subsequent fetch / cancel calls. Handle values are ≥ 1; zero is never
    /// returned in practice.
    func startSearch(
        root: String,
        query: String,
        subtree: Bool,
        showHidden: Bool
    ) async -> UInt64 {
        await Task.detached(priority: .userInitiated) {
            searchStart(root, query, subtree, showHidden)
        }.value
    }

    /// Pulls the next batch of matches. Returns `nil` when the walker has
    /// finished (done / capped / cancelled). An empty array means "keep-alive"
    /// — the walker is still running but produced no new matches in the last
    /// ~100ms tick; the caller should loop again.
    func fetchSearchBatch(handle: UInt64) async -> [FileEntry]? {
        await Task.detached(priority: .userInitiated) {
            let batch = searchNextBatch(handle)
            if batch.isEnd() { return nil }
            let n = Int(batch.len())
            var out: [FileEntry] = []
            out.reserveCapacity(n)
            for i in 0..<n {
                out.append(batch.entry(UInt(i)))
            }
            return out
        }.value
    }

    /// Idempotent cancellation. Safe to call on stale / unknown handles.
    func cancelSearch(handle: UInt64) {
        searchCancel(handle)
    }
}
