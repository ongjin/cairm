import Foundation
import Observation

enum CompareDirection {
    case leftToRight
    case rightToLeft
}

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
    var result = CompareResult()
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

    func applySync(direction: CompareDirection,
                   selected: Set<String>,
                   leftRoot: FSPath,
                   rightRoot: FSPath,
                   transfers: TransferController,
                   leftProvider: FileSystemProvider? = nil,
                   rightProvider: FileSystemProvider? = nil,
                   onComplete: (@MainActor () -> Void)? = nil) {
        let pool: [CompareEntry]
        let srcRoot: FSPath
        let dstRoot: FSPath
        let srcProvider: FileSystemProvider?
        let dstProvider: FileSystemProvider?

        switch direction {
        case .leftToRight:
            pool = result.onlyLeft + result.changed
            srcRoot = leftRoot
            dstRoot = rightRoot
            srcProvider = leftProvider
            dstProvider = rightProvider
        case .rightToLeft:
            pool = result.onlyRight + result.changed
            srcRoot = rightRoot
            dstRoot = leftRoot
            srcProvider = rightProvider
            dstProvider = leftProvider
        }

        for entry in pool where selected.contains(entry.name) {
            let source = srcRoot.appending(entry.name)
            let destination = dstRoot.appending(entry.name)
            let size = entry.size

            transfers.enqueue(source: source, destination: destination, sizeHint: size, onComplete: onComplete) { job, progress in
                try await Self.copy(
                    source: source,
                    destination: destination,
                    size: size,
                    sourceProvider: srcProvider,
                    destinationProvider: dstProvider,
                    job: job,
                    progress: progress
                )
            }
        }
    }

    private func compareEntry(from entry: FileEntry) -> CompareEntry {
        CompareEntry(
            name: entry.name.toString(),
            size: Int64(clamping: entry.size),
            mtime: Date(timeIntervalSince1970: TimeInterval(entry.modified_unix)),
            isDirectory: entry.kind == .Directory
        )
    }

    private static func copy(source: FSPath,
                             destination: FSPath,
                             size: Int64,
                             sourceProvider: FileSystemProvider?,
                             destinationProvider: FileSystemProvider?,
                             job: TransferJob,
                             progress: @escaping (Int64) -> Void) async throws {
        guard let sourceProvider, let destinationProvider else { return }

        switch (source.provider, destination.provider) {
        case (.local, .local):
            let sourceURL = URL(fileURLWithPath: source.path)
            let destinationURL = URL(fileURLWithPath: destination.path)
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            progress(size)
        case (.local, .ssh):
            let sourceURL = URL(fileURLWithPath: source.path)
            try await destinationProvider.uploadFromLocal(
                sourceURL,
                to: destination,
                progress: progress,
                cancel: job.cancel
            )
        case (.ssh, .local):
            let destinationURL = URL(fileURLWithPath: destination.path)
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try await sourceProvider.downloadToLocal(
                source,
                toLocalURL: destinationURL,
                progress: progress,
                cancel: job.cancel
            )
        case (.ssh(let sourceTarget), .ssh(let destinationTarget)) where sourceTarget == destinationTarget:
            try await sourceProvider.copyInPlace(from: source, to: destination)
            progress(size)
        default:
            throw FileSystemError.unsupported
        }
    }
}
