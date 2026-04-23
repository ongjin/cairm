import SwiftUI
import UniformTypeIdentifiers

/// A single tab "chip" rendered in `TabBarView`. Displays a folder icon, the
/// folder's last path component, and a close button that appears on hover or
/// while the chip is active. Activation fires `onActivate`; clicking the × fires
/// `onClose`. All styling flows from the current `CairnTheme`.
///
/// Added in M1.8 T13. Uses a fixed 180pt width (Warp-style) so chips stay a
/// consistent size as tabs are added; long names truncate in the middle.
struct TabChip: View {
    static let width: CGFloat = 180

    let label: String
    let isActive: Bool
    var badge: String? = nil
    let onActivate: () -> Void
    let onClose: () -> Void

    @Environment(\.cairnTheme) private var theme
    @State private var hovering = false
    /// True while a drag is hovering over the chip. Used to trigger spring-
    /// loaded tab activation so the user can drop into the newly-switched tab.
    @State private var dragTargeted = false
    @State private var springLoadTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 6) {
            if let badge {
                Text(badge)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color(red: 0.66, green: 0.94, blue: 0.84))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color(red: 0.39, green: 0.78, blue: 0.70).opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            Text(label)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            if hovering || isActive {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(width: TabChip.width, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                .fill(isActive ? theme.accentMuted : Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                .stroke(isActive ? theme.accent.opacity(0.35) : Color.clear, lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onActivate)
        .onHover { hovering = $0 }
        // Spring-loaded activation: hover with a drag for ~400ms to switch to
        // this tab, enabling cross-tab drag-drop without dropping first.
        // `.fileURL` + `.cairnFSPath` cover both local and SSH sources.
        .onDrop(
            of: [UTType.fileURL] + (UTType("com.cairn.fspath").map { [$0] } ?? []),
            isTargeted: Binding(
                get: { dragTargeted },
                set: { newValue in
                    dragTargeted = newValue
                    if newValue, !isActive {
                        springLoadTask?.cancel()
                        springLoadTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 400_000_000)
                            if !Task.isCancelled, dragTargeted, !isActive {
                                onActivate()
                            }
                        }
                    } else {
                        springLoadTask?.cancel()
                        springLoadTask = nil
                    }
                }
            ),
            perform: { _ in false }  // never consume; the drop belongs to the tab's content
        )
    }
}
