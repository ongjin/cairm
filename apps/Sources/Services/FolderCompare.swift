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

    static func compareRecursive(leftRoot: String,
                                 leftProvider: FileSystemProvider,
                                 rightRoot: String,
                                 rightProvider: FileSystemProvider,
                                 mode: CompareMode,
                                 cancel: CancelToken,
                                 onProgress: (Int) -> Void = { _ in }) async throws -> CompareResult {
        async let leftEntries = walkFiles(
            root: leftRoot,
            provider: leftProvider,
            cancel: cancel,
            onProgress: onProgress
        )
        async let rightEntries = walkFiles(
            root: rightRoot,
            provider: rightProvider,
            cancel: cancel,
            onProgress: onProgress
        )
        return compare(left: try await leftEntries, right: try await rightEntries, mode: mode)
    }

    private static func walkFiles(root: String,
                                  provider: FileSystemProvider,
                                  cancel: CancelToken,
                                  onProgress: (Int) -> Void) async throws -> [CompareEntry] {
        var files: [CompareEntry] = []
        var stack = [""]

        while let relativeParent = stack.popLast() {
            if cancel.isCancelled { return files }
            let path = FSPath(
                provider: provider.identifier,
                path: root + (relativeParent.isEmpty ? "" : "/" + relativeParent)
            )
            let entries = try await provider.list(path)

            for entry in entries {
                if cancel.isCancelled { return files }
                let relName = relativeName(for: entry, parent: relativeParent)
                if entry.kind == .Directory {
                    stack.append(relName)
                } else {
                    files.append(compareEntry(from: entry, relativeName: relName))
                    onProgress(files.count)
                }
            }
        }

        return files
    }

    private static func relativeName(for entry: FileEntry, parent: String) -> String {
        let name = entry.name.toString()
        return parent.isEmpty ? name : parent + "/" + name
    }

    private static func compareEntry(from entry: FileEntry, relativeName: String) -> CompareEntry {
        CompareEntry(
            name: relativeName,
            size: Int64(clamping: entry.size),
            mtime: Date(timeIntervalSince1970: TimeInterval(entry.modified_unix)),
            isDirectory: entry.kind == .Directory
        )
    }
}
