import Foundation
import Observation

@MainActor
@Observable
final class FolderCompareModel {
    enum Phase: Equatable {
        case idle
        case running
        case done
        case failed(String)
        case cancelled
    }

    private(set) var phase: Phase = .idle
    private(set) var result = CompareResult()
    private(set) var scannedCount = 0

    private var task: Task<Void, Never>?
    private var cancel: CancelToken?

    func run(leftRoot: FSPath,
             rightRoot: FSPath,
             leftProvider: FileSystemProvider,
             rightProvider: FileSystemProvider,
             mode: CompareMode,
             recursive: Bool) async {
        cancelRunning()
        phase = .running
        result = CompareResult()
        scannedCount = 0

        let token = CancelToken()
        cancel = token

        do {
            let nextResult: CompareResult
            if recursive {
                nextResult = try await FolderCompare.compareRecursive(
                    leftRoot: leftRoot.path,
                    leftProvider: leftProvider,
                    rightRoot: rightRoot.path,
                    rightProvider: rightProvider,
                    mode: mode,
                    cancel: token,
                    onProgress: { [weak self] count in
                        Task { @MainActor in
                            self?.scannedCount = count
                        }
                    }
                )
            } else {
                async let leftEntries = leftProvider.list(leftRoot)
                async let rightEntries = rightProvider.list(rightRoot)
                let (leftList, rightList) = try await (leftEntries, rightEntries)
                nextResult = FolderCompare.compare(
                    left: leftList.map(compareEntry),
                    right: rightList.map(compareEntry),
                    mode: mode
                )
            }

            result = nextResult
            phase = token.isCancelled ? .cancelled : .done
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    func cancelRunning() {
        cancel?.cancel()
        task?.cancel()
        phase = .cancelled
    }

    private func compareEntry(from entry: FileEntry) -> CompareEntry {
        CompareEntry(
            name: entry.name.toString(),
            size: Int64(clamping: entry.size),
            mtime: Date(timeIntervalSince1970: TimeInterval(entry.modified_unix)),
            isDirectory: entry.kind == .Directory
        )
    }
}
