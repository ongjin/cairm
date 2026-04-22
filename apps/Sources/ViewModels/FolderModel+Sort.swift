import Foundation

extension FolderModel {
    /// Stateless comparator for `FileEntry` pairs implementing Cairn's
    /// "directories first, then by sort field" ordering.
    ///
    /// Shared between `FolderModel.sortedEntries` (the normal folder view) and
    /// `SearchModel`'s running-sort (search results) so both surfaces produce
    /// the same visual order for the same descriptor.
    static func comparator(for sort: SortDescriptor)
        -> (FileEntry, FileEntry) -> Bool
    {
        { a, b in
            let aIsDir = a.kind == .Directory
            let bIsDir = b.kind == .Directory
            if aIsDir != bIsDir {
                return aIsDir // directories bubble to the top regardless of order
            }
            let asc = (sort.order == .ascending)
            switch sort.field {
            case .name:
                let l = a.name.toString().lowercased()
                let r = b.name.toString().lowercased()
                return asc ? (l < r) : (l > r)
            case .size:
                return asc ? (a.size < b.size) : (a.size > b.size)
            case .modified:
                return asc ? (a.modified_unix < b.modified_unix)
                           : (a.modified_unix > b.modified_unix)
            }
        }
    }

    /// Optimised name sort: lowercases each entry's name exactly once into a
    /// sort key, sorts the (entry, key) pairs, then strips the keys. For an
    /// N-entry sort this collapses ~2·N·log(N) `lowercased()` allocations
    /// (one per side per comparison) down to N. Preserves the same
    /// "directories first, then by lowercased name" ordering as
    /// `comparator(for:)`'s `.name` branch — semantics are identical, only
    /// the allocation cost changes.
    static func sortedByName(_ entries: [FileEntry], order: SortOrder) -> [FileEntry] {
        struct Keyed {
            let entry: FileEntry
            let isDir: Bool
            let key: String
        }
        let asc = (order == .ascending)
        let decorated: [Keyed] = entries.map { e in
            Keyed(entry: e,
                  isDir: e.kind == .Directory,
                  key: e.name.toString().lowercased())
        }
        let sorted = decorated.sorted { a, b in
            if a.isDir != b.isDir { return a.isDir }
            return asc ? (a.key < b.key) : (a.key > b.key)
        }
        return sorted.map(\.entry)
    }
}
