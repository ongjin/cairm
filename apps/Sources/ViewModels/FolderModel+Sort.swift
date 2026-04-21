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
}
