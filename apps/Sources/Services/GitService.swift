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
        var dirtyCount: Int { modifiedCount + untrackedCount + addedCount + deletedCount }
    }

    init(root: URL) {
        self.root = root
        refresh()
    }

    func refresh() {
        let s = ffi_git_snapshot(root.path)
        guard let s else { self.snapshot = nil; return }
        let branch = s.branch.toString()
        self.snapshot = Snapshot(
            branch: branch.isEmpty ? nil : branch,
            modifiedCount: Int(s.modified_count),
            untrackedCount: Int(s.untracked_count),
            addedCount: Int(s.added_count),
            deletedCount: Int(s.deleted_count)
        )
    }
}
