import SwiftUI

struct CompareRow: View {
    let entry: CompareEntry
    @Binding var isSelected: Bool
    let bucketColor: Color

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: $isSelected)
                .labelsHidden()
            Image(systemName: entry.isDirectory ? "folder" : "doc")
                .foregroundStyle(bucketColor)
            Text(entry.name)
                .font(.system(size: 12))
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { isSelected.toggle() }
    }
}
