import SwiftUI

struct RemoteHostRow: View {
    let item: SidebarModel.RemoteHostItem
    var onConnect: () -> Void
    var onDisconnect: () -> Void
    var onHide: () -> Void
    var onRevealConfig: () -> Void
    var onCopySshCommand: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
                .shadow(color: dotColor.opacity(0.6), radius: dotGlow, y: 0)
            Text(item.id).lineLimit(1).truncationMode(.middle)
            if item.pinned {
                Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { onConnect() }
        .help(item.displaySummary)
        .contextMenu {
            Button("Connect") { onConnect() }
            Button("Disconnect") { onDisconnect() }
                .disabled(item.state != .connected)
            Divider()
            Button("Copy ssh Command") { onCopySshCommand() }
            Button("Reveal ssh_config Entry") { onRevealConfig() }
            Divider()
            Button("Hide from Sidebar") { onHide() }
        }
    }

    private var dotColor: Color {
        switch item.state {
        case .connected:    return Color(red: 0.42, green: 0.85, blue: 0.61)
        case .idle:         return Color(red: 0.85, green: 0.77, blue: 0.41)
        case .error:        return Color(red: 1.00, green: 0.53, blue: 0.53)
        case .disconnected: return Color(red: 0.33, green: 0.36, blue: 0.42)
        }
    }
    private var dotGlow: CGFloat { item.state == .connected ? 4 : 0 }
}
