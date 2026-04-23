import Foundation
import Observation

@MainActor
@Observable
final class TransferController {
    private(set) var jobs: [TransferJob] = []

    var activeCount: Int {
        jobs.filter { $0.state == .queued || $0.state == .running }.count
    }

    var hasActive: Bool { activeCount > 0 }

    private var runningPerHost: [String?: UUID] = [:]
    private var pendingExecutors: [UUID: (TransferJob, @escaping (Int64) -> Void) async throws -> Void] = [:]

    func enqueue(source: FSPath, destination: FSPath, sizeHint: Int64?,
                 execute: @escaping (_ job: TransferJob, _ progress: @escaping (Int64) -> Void) async throws -> Void) {
        let job = TransferJob(source: source, destination: destination, sizeHint: sizeHint, cancel: CancelToken())
        jobs.append(job)
        pendingExecutors[job.id] = execute
        maybeStartNext()
    }

    func cancel(_ id: UUID) {
        guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[idx].cancel.cancel()
        if jobs[idx].state == .queued {
            jobs[idx].state = .cancelled
            jobs[idx].finishedAt = Date()
        }
    }

    func retry(_ id: UUID) {
        guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
        switch jobs[idx].state {
        case .failed, .cancelled: break
        default: return
        }
        let old = jobs[idx]
        enqueue(source: old.source, destination: old.destination, sizeHint: old.sizeHint,
                execute: pendingExecutors[id] ?? { _, _ in })
    }

    func cancelAll() {
        for id in jobs.map(\.id) { cancel(id) }
    }

    private func maybeStartNext() {
        // Evaluate per-iteration so startJob's lane update is visible to the next check.
        for (idx, j) in jobs.enumerated() {
            guard j.state == .queued, runningPerHost[j.remoteHostKey] == nil else { continue }
            startJob(at: idx)
        }
    }

    private func startJob(at idx: Int) {
        guard idx < jobs.count else { return }
        let host = jobs[idx].remoteHostKey
        let id = jobs[idx].id
        guard let executor = pendingExecutors.removeValue(forKey: id) else { return }
        runningPerHost[host] = id
        jobs[idx].state = .running
        jobs[idx].startedAt = Date()
        Task {
            do {
                try await executor(jobs[idx]) { [weak self] bytes in
                    Task { @MainActor in
                        guard let self, let i = self.jobs.firstIndex(where: { $0.id == id }) else { return }
                        self.jobs[i].bytesCompleted = bytes
                    }
                }
                await MainActor.run {
                    if let i = self.jobs.firstIndex(where: { $0.id == id }) {
                        self.jobs[i].state = .completed
                        self.jobs[i].finishedAt = Date()
                    }
                    self.runningPerHost[host] = nil
                    self.maybeStartNext()
                }
            } catch is CancellationError {
                await MainActor.run {
                    if let i = self.jobs.firstIndex(where: { $0.id == id }) {
                        self.jobs[i].state = .cancelled
                        self.jobs[i].finishedAt = Date()
                    }
                    self.runningPerHost[host] = nil
                    self.maybeStartNext()
                }
            } catch {
                await MainActor.run {
                    if let i = self.jobs.firstIndex(where: { $0.id == id }) {
                        self.jobs[i].state = .failed((error as NSError).localizedDescription)
                        self.jobs[i].finishedAt = Date()
                    }
                    self.runningPerHost[host] = nil
                    self.maybeStartNext()
                }
            }
        }
    }
}
