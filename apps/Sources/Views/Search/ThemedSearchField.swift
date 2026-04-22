import SwiftUI

/// Search field styled to match Cairn's Glass Blue palette. Replaces the
/// default `.roundedBorder` with an accent-tinted rounded rectangle + accent
/// border so the field reads as "search in this app" rather than generic
/// macOS text input. Scope Picker + progress badge unchanged from M1.6.
///
/// Focus is bound externally so `ContentView` can wire `⌘F` → `focused = true`.
struct ThemedSearchField: View {
    @Bindable var search: SearchModel
    @FocusState.Binding var focused: Bool

    @Environment(\.cairnTheme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            Picker("", selection: $search.scope) {
                Text("This Folder").tag(SearchModel.Scope.folder)
                Text("Subtree").tag(SearchModel.Scope.subtree)
            }
            .pickerStyle(.segmented)
            .frame(width: 140)

            TextField("Search", text: $search.query)
                .textFieldStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: theme.cornerRadius)
                        .fill(theme.accentMuted.opacity(0.3))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: theme.cornerRadius)
                        .stroke(theme.accent.opacity(0.4), lineWidth: 1)
                )
                .focused($focused)
                .frame(width: 200)

            if search.phase == .running {
                ProgressView().controlSize(.small)
                Text("\(search.hitCount) found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if search.phase == .capped {
                Text("capped at 5,000")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}
