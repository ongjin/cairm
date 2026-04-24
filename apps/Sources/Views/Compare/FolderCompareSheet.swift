import SwiftUI

struct FolderCompareSheet: View {
    @Bindable var model: FolderCompareModel
    let transfers: TransferController
    let leftRoot: FSPath
    let rightRoot: FSPath
    let leftProvider: FileSystemProvider
    let rightProvider: FileSystemProvider
    let onDismiss: () -> Void

    @State private var mode: CompareMode = .nameSizeMtime
    @State private var recursive = false
    @State private var selected: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.phase == .running {
                ProgressView("Scanning... (\(model.scannedCount))")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                results
            }
            Divider()
            footer
        }
        .frame(minWidth: 680, minHeight: 480)
        .task { await runScan() }
    }

    private var header: some View {
        HStack {
            Text("Compare")
                .font(.title3.bold())
            Spacer()
            Picker("Mode", selection: $mode) {
                Text("Name only").tag(CompareMode.nameOnly)
                Text("+ size").tag(CompareMode.nameSize)
                Text("+ size + mtime").tag(CompareMode.nameSizeMtime)
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
            Toggle("Recursive", isOn: $recursive)
            Button("Rescan") { Task { await runScan() } }
        }
        .padding(12)
    }

    private var results: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                section(title: "Only on left", entries: model.result.onlyLeft, color: .blue)
                section(title: "Only on right", entries: model.result.onlyRight, color: .green)
                section(title: "Changed", entries: model.result.changed, color: .orange)
            }
            .padding(.horizontal, 10)
        }
    }

    private func section(title: String, entries: [CompareEntry], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(title) (\(entries.count))")
                    .font(.headline)
                    .foregroundStyle(color)
                Spacer()
                if !entries.isEmpty {
                    Button("Select all") { selected.formUnion(entries.map(\.name)) }
                    Button("Clear") { selected.subtract(entries.map(\.name)) }
                }
            }
            .padding(.vertical, 6)
            ForEach(entries, id: \.name) { entry in
                CompareRow(
                    entry: entry,
                    isSelected: Binding(
                        get: { selected.contains(entry.name) },
                        set: { isOn in
                            if isOn {
                                selected.insert(entry.name)
                            } else {
                                selected.remove(entry.name)
                            }
                        }
                    ),
                    bucketColor: color
                )
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Close", action: onDismiss)
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button("Copy to left") { apply(.rightToLeft) }
            Button("Copy to right") { apply(.leftToRight) }
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    private func runScan() async {
        await model.run(
            leftRoot: leftRoot,
            rightRoot: rightRoot,
            leftProvider: leftProvider,
            rightProvider: rightProvider,
            mode: mode,
            recursive: recursive
        )
    }

    private func apply(_ direction: CompareDirection) {
        model.applySync(
            direction: direction,
            selected: selected,
            leftRoot: leftRoot,
            rightRoot: rightRoot,
            transfers: transfers,
            leftProvider: leftProvider,
            rightProvider: rightProvider
        )
        onDismiss()
    }
}
