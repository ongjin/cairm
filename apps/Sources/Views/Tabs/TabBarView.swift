import SwiftUI

/// Horizontal tab bar rendered above the main `NavigationSplitView` in
/// `ContentView`. Emits activate / close / new-tab intents into the owning
/// `WindowSceneModel`.
///
/// Added in M1.8 T13. Always visible (even with one tab) to keep the "+" button
/// reachable and to avoid a layout jump when a second tab opens.
struct TabBarView: View {
    @Bindable var scene: WindowSceneModel
    @Environment(\.cairnTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(scene.tabs) { tab in
                        TabChip(
                            label: tab.titleText,
                            isActive: tab.id == scene.activeTabID,
                            badge: tab.protocolBadge,
                            onActivate: { scene.activeTabID = tab.id },
                            onClose: { scene.closeTabOrWindow(tab.id) }
                        )
                    }
                }
                .padding(.horizontal, 10)
            }
            Button(action: { scene.newTab() }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                            .fill(Color.secondary.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .padding(.trailing, 10)
        }
        .padding(.vertical, 5)
        .frame(height: 38)
        .background(.thinMaterial)
    }
}
