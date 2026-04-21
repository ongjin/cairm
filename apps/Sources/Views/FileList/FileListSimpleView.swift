import SwiftUI

/// Minimal 1-column list of entries. Will be replaced by NSTableView-backed
/// FileListView in M1.2; kept here as the scaffolding for M1.1 verification.
struct FileListSimpleView: View {
    @Bindable var folder: FolderModel
    /// Called when the user activates a row (double-click / Return).
    let onOpen: (FileEntry) -> Void

    @State private var selection: FileEntry.ID?

    var body: some View {
        Group {
            switch folder.state {
            case .idle:
                Text("No folder loaded.")
                    .foregroundStyle(.secondary)
            case .loading:
                ProgressView().controlSize(.small)
            case .failed(let message):
                VStack(alignment: .leading, spacing: 4) {
                    Text("Couldn't read folder").font(.headline)
                    Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .padding()
            case .loaded:
                List(folder.entries, id: \.id, selection: $selection) { entry in
                    Label {
                        Text(entry.name.toString())
                    } icon: {
                        Image(systemName: entry.kind == .Directory ? "folder.fill" : "doc")
                            .foregroundStyle(entry.kind == .Directory ? .blue : .secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { onOpen(entry) }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// FileEntry is a swift-bridge struct; it doesn't auto-conform to Identifiable.
// Wrap the path (which is unique within a folder snapshot) as the id.
extension FileEntry: Identifiable {
    public var id: String { path.toString() }
}
