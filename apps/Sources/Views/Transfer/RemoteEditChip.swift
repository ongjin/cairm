import SwiftUI

private let remoteEditAccent = Color(red: 0.95, green: 0.54, blue: 0.24)

struct RemoteEditChip: View {
    @Bindable var controller: RemoteEditController
    @State private var showPopover = false

    private var sessions: [RemoteEditSession] {
        Array(controller.activeSessions.values).sorted(by: { lhs, rhs in
            lhs.remotePath.path < rhs.remotePath.path
        })
    }

    var body: some View {
        if !controller.activeSessions.isEmpty {
            Button {
                showPopover.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pencil.and.outline")
                    Text("Editing \(controller.activeSessions.count)")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(remoteEditAccent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(remoteEditAccent.opacity(0.18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(remoteEditAccent.opacity(0.35))
                        )
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPopover, arrowEdge: .top) {
                sessionList
            }
        }
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(sessions, id: \.id) { session in
                HStack(spacing: 10) {
                    Text(session.remotePath.lastComponent)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 12)

                    Text(describe(session.state))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Button("Finish") {
                        controller.endSession(session.id)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                }
            }
        }
        .padding(10)
        .frame(minWidth: 280)
    }

    private func describe(_ state: RemoteEditState) -> String {
        switch state {
        case .watching:
            return "watching"
        case .uploading(let bytes):
            return "uploading \(bytes)B"
        case .conflict:
            return "conflict"
        case .done:
            return "saved"
        case .failed(let message):
            return "failed: \(message)"
        case .cancelled:
            return "cancelled"
        }
    }
}
