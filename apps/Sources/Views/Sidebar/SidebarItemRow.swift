import SwiftUI

struct SidebarItemRow: View {
    let icon: String
    let label: String
    let tint: Color?
    let isSelected: Bool

    @Environment(\.cairnTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 16)
                .foregroundStyle(tint ?? Color.secondary)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? theme.text : theme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                .fill(isSelected ? theme.accentMuted : Color.clear)
        )
        .contentShape(Rectangle())
    }
}
