import SwiftUI

/// Single sidebar row — icon + label. Used for every section so all items line
/// up visually and we have one place to tune padding/size. When `isSelected`
/// is true, the row gets a theme-accented pill background so the user always
/// knows which source the current folder belongs to.
struct SidebarItemRow: View {
    let icon: String      // SF Symbol name
    let label: String
    let tint: Color?      // if nil, label color is used
    var isSelected: Bool = false

    @Environment(\.cairnTheme) private var theme

    var body: some View {
        Label {
            Text(label)
                .lineLimit(1)
                .truncationMode(.middle)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(tint ?? .primary)
                .frame(width: 16)
        }
        .font(theme.bodyFont)
        .padding(.vertical, 1)
        .padding(.horizontal, 6)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: theme.cornerRadius)
                    .fill(theme.accentMuted)
            }
        }
    }
}
