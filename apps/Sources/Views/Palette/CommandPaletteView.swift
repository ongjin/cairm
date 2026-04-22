import SwiftUI

struct CommandPaletteView: View {
    @Bindable var model: CommandPaletteModel
    let tab: Tab
    let commands: [PaletteCommand]
    let onActivate: (PaletteRowData) -> Void

    @Environment(\.cairnTheme) private var theme
    @FocusState private var queryFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { model.close() }

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text(modeSigil)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(theme.accent)
                        .frame(width: 20)
                    TextField(placeholder, text: Binding(
                        get: { model.query },
                        set: { model.dispatch(tab: tab, query: $0, onCommand: commands) }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($queryFocused)
                    .onSubmit { activateSelected() }
                    .onKeyPress(.downArrow) { model.selectedIndex = min(model.selectedIndex + 1, rowCount - 1); return .handled }
                    .onKeyPress(.upArrow) { model.selectedIndex = max(model.selectedIndex - 1, 0); return .handled }
                    .onKeyPress(.escape) { model.close(); return .handled }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(.regularMaterial)

                Divider()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { (idx, row) in
                            PaletteRow(data: row, isSelected: idx == model.selectedIndex)
                                .contentShape(Rectangle())
                                .onTapGesture { onActivate(row) }
                        }
                    }
                }
                .frame(maxHeight: 320)
                .background(.regularMaterial)
            }
            .frame(width: 640, height: 400, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.accent.opacity(0.2), lineWidth: 1))
            .shadow(radius: 12)
            .onAppear { queryFocused = true }
        }
    }

    private var rows: [PaletteRowData] {
        if !model.commandHits.isEmpty { return model.commandHits.map { .command($0) } }
        if !model.contentHits.isEmpty { return model.contentHits.map { .content($0) } }
        if !model.symbolHits.isEmpty  { return model.symbolHits.map  { .symbol($0) } }
        return model.fileHits.map { .file($0) }
    }

    private var rowCount: Int { rows.count }

    private var modeSigil: String {
        switch CommandPaletteModel.parse(model.query) {
        case .fuzzy:    return "\u{203A}"
        case .command:  return ">"
        case .content:  return "/"
        case .gitDirty: return "#"
        case .symbol:   return "@"
        }
    }

    private var placeholder: String {
        switch CommandPaletteModel.parse(model.query) {
        case .fuzzy:    return "Find files\u{2026}"
        case .command:  return "Run command\u{2026}"
        case .content:  return "Search file contents\u{2026}"
        case .gitDirty: return "Filter dirty files\u{2026}"
        case .symbol:   return "Jump to symbol\u{2026}"
        }
    }

    private func activateSelected() {
        guard model.selectedIndex < rows.count else { return }
        onActivate(rows[model.selectedIndex])
    }
}
