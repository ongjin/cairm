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
    func refresh() {
        let s = ffi_git_snapshot(root.path)
        guard let s else { self.snapshot = nil; return }
        let branch = s.branch.toString()
        let mods = Self.loadPaths(ffi_git_modified_paths(root.path))
        let adds = Self.loadPaths(ffi_git_added_paths(root.path))
        let dels = Self.loadPaths(ffi_git_deleted_paths(root.path))
        let untr = Self.loadPaths(ffi_git_untracked_paths(root.path))

        // Build the consolidated status dict. Insertion order matters when a
        // path appears in multiple sets (libgit2 occasionally reports a file
        // as both modified and untracked in edge cases like submodules);
        // earliest insertion wins, matching the original switch order in the
        // file-list git column (modified > added > deleted > untracked).
        var byPath: [String: GitStatus] = [:]
        byPath.reserveCapacity(mods.count + adds.count + dels.count + untr.count)
        for p in mods where byPath[p] == nil { byPath[p] = .modified }
        for p in adds where byPath[p] == nil { byPath[p] = .added }
        for p in dels where byPath[p] == nil { byPath[p] = .deleted }
        for p in untr where byPath[p] == nil { byPath[p] = .untracked }

        self.snapshot = Snapshot(
            branch: branch.isEmpty ? nil : branch,
            modifiedCount: Int(s.modified_count),
            untrackedCount: Int(s.untracked_count),
            addedCount: Int(s.added_count),
            deletedCount: Int(s.deleted_count),
            statusByPath: byPath
        )
    }

    private static func loadPaths(_ list: GitPathList) -> [String] {
        var out: [String] = []
        let n = list.len()
        out.reserveCapacity(Int(n))
        var i: UInt = 0
        while i < n {
            out.append(list.at(i).toString())
            i += 1
        }
        return out
    }
}
