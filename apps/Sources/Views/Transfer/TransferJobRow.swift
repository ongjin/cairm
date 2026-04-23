import SwiftUI

struct TransferJobRow: View {
    let job: TransferJob
    var onCancel: () -> Void
    var onRetry: () -> Void

    private static let byteFormatter = ByteCountFormatter()

    private var needsRetry: Bool {
        switch job.state {
        case .failed, .cancelled: return true
        default: return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(directionIcon).font(.system(size: 12))
                Text(job.source.lastComponent).lineLimit(1).truncationMode(.middle)
                Spacer()
                rightSide
            }.font(.system(size: 11))

            if job.state == .running, let pct = job.percent {
                ProgressView(value: pct, total: 100)
                    .progressViewStyle(.linear)
                    .tint(.green)
            } else if job.state == .queued {
                Text("Queued")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }

            HStack(spacing: 8) {
                Text(destinationSummary).font(.system(size: 10)).foregroundStyle(.secondary)
                if let sp = job.speed {
                    Text(TransferJobRow.byteFormatter.string(fromByteCount: Int64(sp)) + "/s")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                if let eta = job.eta {
                    Text("ETA " + formatDuration(eta))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                if needsRetry {
                    Button("Retry", action: onRetry).buttonStyle(.link).font(.system(size: 10))
                }
                if job.state == .running || job.state == .queued {
                    Button("Cancel", action: onCancel).buttonStyle(.link).font(.system(size: 10))
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var directionIcon: String {
        if case .ssh = job.source.provider, case .local = job.destination.provider { return "⬇" }
        if case .local = job.source.provider, case .ssh = job.destination.provider { return "⬆" }
        return "⇄"
    }

    @ViewBuilder
    private var rightSide: some View {
        switch job.state {
        case .completed:
            Text("✓").foregroundStyle(.green).font(.system(size: 11, weight: .semibold))
        case .cancelled:
            Text("✕").foregroundStyle(.secondary).font(.system(size: 11, weight: .semibold))
        case .failed:
            Text("⚠︎").foregroundStyle(.red).font(.system(size: 11, weight: .semibold))
        case .running:
            if let p = job.percent {
                Text("\(Int(p))%").foregroundStyle(.primary).font(.system(size: 11, weight: .semibold))
            }
        case .queued:
            EmptyView()
        }
    }

    private var destinationSummary: String {
        switch job.destination.provider {
        case .ssh(let t): return "to \(t.hostname):\(job.destination.parent()?.path ?? "/")"
        case .local:      return "to \(job.destination.parent()?.path ?? "/")"
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \(s % 3600 / 60)m"
    }
}
