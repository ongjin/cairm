import SwiftUI

/// Toolbar search component. Holds a scope Picker (This Folder / Subtree)
/// and the query text field. Progress badge appears during subtree streaming.
/// Focus is bound externally so `ContentView` can wire `⌘F` to `focused = true`.
struct SearchField: View {
    @Bindable var search: SearchModel
    @FocusState.Binding var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Picker("", selection: $search.scope) {
                Text("This Folder").tag(SearchModel.Scope.folder)
                Text("Subtree").tag(SearchModel.Scope.subtree)
            }
            .pickerStyle(.segmented)
            .frame(width: 140)

            TextField("Search", text: $search.query)
                .textFieldStyle(.roundedBorder)
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
