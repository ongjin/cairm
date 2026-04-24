import Foundation

struct CompareEntry: Equatable {
    let name: String
    let size: Int64
    let mtime: Date
    let isDirectory: Bool
}

enum CompareMode {
    case nameOnly
    case nameSize
    case nameSizeMtime
}

struct CompareResult: Equatable {
    var onlyLeft: [CompareEntry] = []
    var onlyRight: [CompareEntry] = []
    var changed: [CompareEntry] = []
    var same: [CompareEntry] = []
}

enum FolderCompare {
    /// Pure diff over two flat entry lists. Comparison keys:
    /// - nameOnly: presence alone
    /// - nameSize: size equality
    /// - nameSizeMtime: size and mtime equality within +/- 2s
    static func compare(left: [CompareEntry],
                        right: [CompareEntry],
                        mode: CompareMode) -> CompareResult {
        var result = CompareResult()
        let rightByName = Dictionary(uniqueKeysWithValues: right.map { ($0.name, $0) })
        var seen = Set<String>()

        for l in left {
            if let r = rightByName[l.name] {
                seen.insert(l.name)
                if isEqual(l, r, mode: mode) {
                    result.same.append(l)
                } else {
                    result.changed.append(l)
                }
            } else {
                result.onlyLeft.append(l)
            }
        }
        for r in right where !seen.contains(r.name) {
            result.onlyRight.append(r)
        }
        return result
    }

    private static func isEqual(_ a: CompareEntry, _ b: CompareEntry, mode: CompareMode) -> Bool {
        switch mode {
        case .nameOnly:
            return true
        case .nameSize:
            return a.size == b.size
        case .nameSizeMtime:
            return a.size == b.size && abs(a.mtime.timeIntervalSince(b.mtime)) <= 2
        }
    }
}
