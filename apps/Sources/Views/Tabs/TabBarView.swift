import SwiftUI

/// Horizontal tab bar rendered above the main `NavigationSplitView` in
/// `ContentView`. Emits activate / close / new-tab intents into the owning
/// `WindowSceneModel`.
///
/// Added in M1.8 T13. Always visible (even with one tab) to keep the "+" button
/// reachable and to avoid a layout jump when a second tab opens.
struct TabBarView: View {
    @Bindable var scene: WindowSceneModel

    var body: some View {
        HStack(spacing: 8) {
            ForEach(scene.tabs) { tab in
                TabChip(
                    label: tab.currentFolder?.lastPathComponent ?? "Untitled",
                    isActive: tab.id == scene.activeTabID,
                    onActivate: { scene.activeTabID = tab.id },
                    onClose: { scene.closeTab(tab.id) }
                )
            }
            Button(action: { scene.newTab() }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.secondary.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(height: 36)
        .background(.thinMaterial)
    }
}
