import SwiftUI

/// Single sidebar row — icon + label. Used for every section so all items line
/// up visually and we have one place to tune padding/size.
struct SidebarItemRow: View {
    let icon: String      // SF Symbol name
    let label: String
    let tint: Color?      // if nil, label color is used

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
        .font(.system(size: 12))
        .padding(.vertical, 1)
    }
}
