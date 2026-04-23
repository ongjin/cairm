import SwiftUI

struct TransferPopoverView: View {
    @Bindable var controller: TransferController

    private var active: [TransferJob] {
        controller.jobs.filter { $0.state == .running || $0.state == .queued }
    }
    private var recent: [TransferJob] {
        Array(controller.jobs.filter { j in
            switch j.state { case .completed, .cancelled, .failed: return true; default: return false }
        }.suffix(10).reversed())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !active.isEmpty {
                sectionHeader("Active Transfers")
                ForEach(active) { job in
                    TransferJobRow(job: job,
                                   onCancel: { controller.cancel(job.id) },
                                   onRetry: { controller.retry(job.id) })
                        .padding(.horizontal, 10)
                    Divider().padding(.leading, 10)
                }
            }
            if !recent.isEmpty {
                sectionHeader("Recent")
                ForEach(recent) { job in
                    TransferJobRow(job: job,
                                   onCancel: { controller.cancel(job.id) },
                                   onRetry: { controller.retry(job.id) })
                        .padding(.horizontal, 10)
                    Divider().padding(.leading, 10)
                }
            }
        }
        .padding(.vertical, 8)
        .frame(minWidth: 340)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 2)
    }
}
