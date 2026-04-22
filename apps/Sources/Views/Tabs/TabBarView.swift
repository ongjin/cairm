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
        HStack(spacing: 6) {
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
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(height: 32)
        .background(.thinMaterial)
    }
}
