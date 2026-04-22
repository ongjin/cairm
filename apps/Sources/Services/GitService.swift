import Foundation
import Observation

@Observable
final class GitService {
    /// Per-file git status surfaced in the file-list "Git" column. Tracked
    /// states only — files with no entry in `statusByPath` are clean.
    enum GitStatus {
        case modified
        case added
        case deleted
        case untracked
    }

    let root: URL
    private(set) var snapshot: Snapshot?

    struct Snapshot {
        let branch: String?
        let modifiedCount: Int
        let untrackedCount: Int
        let addedCount: Int
        let deletedCount: Int
        /// Single dict keyed by repo-relative path. Replaces the previous
        /// 4-Set storage so the file-list git column does one lookup per row
        /// instead of up to 4 sequential `.contains()` probes (40K -> 10K
        /// hashes on a 10K-row folder).
        let statusByPath: [String: GitStatus]

        var dirtyCount: Int { modifiedCount + untrackedCount + addedCount + deletedCount }

        /// Backward-compat derived views — kept so other callers that read
        /// the per-state set don't break. The file-list git column should
        /// use `statusByPath` directly.
        var modifiedPaths: Set<String> {
            Set(statusByPath.compactMap { $0.value == .modified ? $0.key : nil })
        }
        var addedPaths: Set<String> {
            Set(statusByPath.compactMap { $0.value == .added ? $0.key : nil })
        }
        var deletedPaths: Set<String> {
            Set(statusByPath.compactMap { $0.value == .deleted ? $0.key : nil })
        }
        var untrackedPaths: Set<String> {
            Set(statusByPath.compactMap { $0.value == .untracked ? $0.key : nil })
        }
    }

    init(root: URL) {
        self.root = root
        refresh()
    }

    /// Synchronous — libgit2 under the hood. Call from main, debounced by caller.
    ///
    /// Single FFI hop into `ffi_git_full_snapshot` does ONE libgit2 status walk
    /// and returns branch + counts + all four path lists. Replaces the old
    /// 5-call sequence (`ffi_git_snapshot` + 4× `ffi_git_*_paths`), each of
    /// which re-ran `cairn_git::snapshot::snapshot()` — i.e. 5 FFI hops and
    /// 4 redundant repo scans per refresh, 50–500ms wasted on the main thread
    /// for moderate repos.
    func refresh() {
        guard let full = ffi_git_full_snapshot(root.path) else {
            self.snapshot = nil
            return
        }
        let branch = full.branch().toString()
        let modifiedCount = Int(full.modified_count())
        let addedCount = Int(full.added_count())
        let deletedCount = Int(full.deleted_count())
        let untrackedCount = Int(full.untracked_count())

        // Build the consolidated status dict. Insertion order matters when a
        // path appears in multiple sets (libgit2 occasionally reports a file
        // as both modified and untracked in edge cases like submodules);
        // earliest insertion wins, matching the original switch order in the
        // file-list git column (modified > added > deleted > untracked).
        var byPath: [String: GitStatus] = [:]
        byPath.reserveCapacity(modifiedCount + addedCount + deletedCount + untrackedCount)
        Self.collect(into: &byPath, count: full.modified_len(), status: .modified) {
            full.modified_at($0).toString()
        }
        Self.collect(into: &byPath, count: full.added_len(), status: .added) {
            full.added_at($0).toString()
        }
        Self.collect(into: &byPath, count: full.deleted_len(), status: .deleted) {
            full.deleted_at($0).toString()
        }
        Self.collect(into: &byPath, count: full.untracked_len(), status: .untracked) {
            full.untracked_at($0).toString()
        }

        self.snapshot = Snapshot(
            branch: branch.isEmpty ? nil : branch,
            modifiedCount: modifiedCount,
            untrackedCount: untrackedCount,
            addedCount: addedCount,
            deletedCount: deletedCount,
            statusByPath: byPath
        )
    }

    private static func collect(
        into byPath: inout [String: GitStatus],
        count: UInt,
        status: GitStatus,
        path: (UInt) -> String
    ) {
        var i: UInt = 0
        while i < count {
            let p = path(i)
            if byPath[p] == nil { byPath[p] = status }
            i += 1
        }
    }
}
