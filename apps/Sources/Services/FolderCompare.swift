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
    static func compare(left: [CompareEntry],
                        right: [CompareEntry],
                        mode: CompareMode) -> CompareResult {
        var result = CompareResult()
        let rightByName = Dictionary(uniqueKeysWithValues: right.map { ($0.name, $0) })

        for l in left {
            if rightByName[l.name] != nil {
                result.same.append(l)
            }
        }
        return result
    }
}
