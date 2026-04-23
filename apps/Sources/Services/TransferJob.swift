import Foundation

struct TransferJob: Identifiable, Equatable {
    let id = UUID()
    let source: FSPath
    let destination: FSPath
    let sizeHint: Int64?
    var bytesCompleted: Int64 = 0
    var state: State = .queued
    var startedAt: Date? = nil
    var finishedAt: Date? = nil
    let cancel: CancelToken

    enum State: Equatable {
        case queued
        case running
        case completed
        case cancelled
        case failed(String)
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }

    var percent: Double? {
        guard let s = sizeHint, s > 0 else { return nil }
        return min(100, Double(bytesCompleted) / Double(s) * 100)
    }

    var speed: Double? {
        guard let start = startedAt, state == .running else { return nil }
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed > 0.5 else { return nil }
        return Double(bytesCompleted) / elapsed
    }

    var eta: TimeInterval? {
        guard let s = sizeHint, let sp = speed, sp > 0, s > bytesCompleted else { return nil }
        return Double(s - bytesCompleted) / sp
    }

    var remoteHostKey: String? {
        if case .ssh(let t) = source.provider { return "\(t.user)@\(t.hostname):\(t.port)" }
        if case .ssh(let t) = destination.provider { return "\(t.user)@\(t.hostname):\(t.port)" }
        return nil
    }
}
