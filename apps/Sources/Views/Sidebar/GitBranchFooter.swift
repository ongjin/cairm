import SwiftUI

/// Compact footer pinned to the bottom of `SidebarView` when the active tab
/// sits inside a git repo. Shows the branch name and, if there are
/// uncommitted changes, a dirty-count badge.
struct GitBranchFooter: View {
    let branch: String
    let dirtyCount: Int

    @Environment(\.cairnTheme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(theme.accent)
            Text(branch)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            if dirtyCount > 0 {
                Text("• \(dirtyCount)")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.08))
    }
}
