import Foundation
import Observation

@Observable
final class GitService {
    let root: URL
    private(set) var snapshot: Snapshot?

    struct Snapshot {
        let branch: String?
        let modifiedCount: Int
        let untrackedCount: Int
        let addedCount: Int
        let deletedCount: Int
        let modifiedPaths: Set<String>
        let untrackedPaths: Set<String>
        let addedPaths: Set<String>
        let deletedPaths: Set<String>
        var dirtyCount: Int { modifiedCount + untrackedCount + addedCount + deletedCount }
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
        self.snapshot = Snapshot(
            branch: branch.isEmpty ? nil : branch,
            modifiedCount: Int(s.modified_count),
            untrackedCount: Int(s.untracked_count),
            addedCount: Int(s.added_count),
            deletedCount: Int(s.deleted_count),
            modifiedPaths: mods,
            untrackedPaths: untr,
            addedPaths: adds,
            deletedPaths: dels
        )
    }

    private static func loadPaths(_ list: GitPathList) -> Set<String> {
        var out = Set<String>()
        let n = list.len()
        var i: UInt = 0
        while i < n {
            out.insert(list.at(i).toString())
            i += 1
        }
        return out
    }
}
