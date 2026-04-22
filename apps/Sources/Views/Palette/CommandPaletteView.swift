import SwiftUI

struct CommandPaletteView: View {
    @Bindable var model: CommandPaletteModel
    let tab: Tab
    let commands: [PaletteCommand]
    let onActivate: (PaletteRowData) -> Void

    @Environment(\.cairnTheme) private var theme
    @FocusState private var queryFocused: Bool
    /// Local input state separated from `model.query`. Two reasons:
    ///   1. The previous Binding(get:set:) pattern asked the model to re-set
    ///      query="" inside the setter when consuming a sigil; SwiftUI's
    ///      TextField didn't reliably refresh its display because the buffer
    ///      lives in the underlying NSTextField, not the binding source.
    ///   2. Backspace handling needs to detect "TextField is empty" cleanly,
    ///      which is easier when we own the input state.
    /// Synced both directions: typing -> `onChange(inputText)`; programmatic
    /// clears (mode switch / consume-backspace) -> `onChange(model.query)`.
    @State private var inputText: String = ""

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { model.close() }

            VStack(spacing: 0) {
                inputBar
                Divider()
                resultsList
                Divider()
                PaletteLegend()
            }
            .frame(width: 640)
            .fixedSize(horizontal: false, vertical: true)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.accent.opacity(0.2), lineWidth: 1))
            .shadow(radius: 12)
        }
        // Top-level escape — works even if the TextField loses focus.
        .onKeyPress(.escape) { model.close(); return .handled }
        // Top-level backspace catches the case where the focused TextField
        // silently swallows the keypress because it has nothing to delete.
        // Only consumes when input is empty AND we're in a non-fuzzy mode;
        // otherwise lets the TextField handle real deletion.
        .onKeyPress(.delete) {
            if inputText.isEmpty && model.mode != .fuzzy {
                model.mode = .fuzzy
                model.runQuery(tab: tab, commands: commands)
                return .handled
            }
            return .ignored
        }
        // Re-assert focus whenever the palette opens. `.onAppear` alone was
        // unreliable because the menu-driven open path momentarily holds
        // focus elsewhere; deferring to the next runloop lets the
        // first-responder dance settle before we claim it.
        .task(id: model.isOpen) {
            if model.isOpen { await refocusSoon() }
        }
        .onAppear {
            inputText = model.query
            Task { await refocusSoon() }
        }
        // Programmatic query clears (mode switch, backspace consume) need to
        // be mirrored back into the local @State so the TextField updates.
        .onChange(of: model.query) { _, newValue in
            if inputText != newValue { inputText = newValue }
        }
    }

    // MARK: - Subviews

    private var inputBar: some View {
        HStack(spacing: 8) {
            Text(model.mode.sigil)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.accent)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 5).fill(theme.accentMuted))
            TextField(model.mode.placeholder, text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($queryFocused)
                .onChange(of: inputText) { _, newValue in
                    handleInputChange(newValue)
                }
                .onKeyPress(.return) { activateSelected(); return .handled }
                .onKeyPress(.downArrow) {
                    model.selectedIndex = min(model.selectedIndex + 1, max(rowCount - 1, 0))
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    model.selectedIndex = max(model.selectedIndex - 1, 0)
                    return .handled
                }
                .onKeyPress(.delete) {
                    if inputText.isEmpty && model.mode != .fuzzy {
                        model.mode = .fuzzy
                        model.runQuery(tab: tab, commands: commands)
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.escape) { model.close(); return .handled }

            if model.mode == .content {
                Button {
                    model.contentIsRegex.toggle()
                    model.runQuery(tab: tab, commands: commands)
                } label: {
                    Text(".*")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(model.contentIsRegex ? .white : .secondary)
                        .frame(width: 26, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(model.contentIsRegex ? theme.accent : Color.secondary.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)
                .help(model.contentIsRegex ? "Regex on — click for literal" : "Literal — click for regex")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        // Click anywhere on the input bar (not just the text glyph area)
        // grabs focus. Without this, clicking the sigil chip or empty
        // padding leaves focus stranded.
        .contentShape(Rectangle())
        .onTapGesture { queryFocused = true }
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if rows.isEmpty, indexBuilding {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Indexing folder… results will appear shortly.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                    ForEach(Array(rows.enumerated()), id: \.offset) { (idx, row) in
                        PaletteRow(data: row, isSelected: idx == model.selectedIndex)
                            .id(idx)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.selectedIndex = idx
                                onActivate(row)
                            }
                    }
                }
            }
            // Keep the keyboard-selected row in view. We pass `anchor: nil`
            // so SwiftUI does the minimum scroll required to make the row
            // visible — no movement when it's already on screen, no bounce
            // when ↑/↓ traverses already-visible rows, and the first result
            // appears at the top instead of being yanked to viewport-center.
            // No animation either: instant scroll feels tighter than a 80ms
            // ease and removes the visible bounce some users were seeing.
            .onChange(of: model.selectedIndex) { _, idx in
                proxy.scrollTo(idx, anchor: nil)
            }
        }
        .frame(minHeight: rows.isEmpty && !indexBuilding ? 0 : 60,
               maxHeight: 360)
        .background(.regularMaterial)
    }

    // MARK: - Behavior

    /// Intercepts a leading sigil typed when the input is empty + mode is
    /// fuzzy: switches mode and clears the buffer so the sigil is not echoed.
    /// Other input flows straight through to `model.query`.
    private func handleInputChange(_ raw: String) {
        if model.mode == .fuzzy, raw.count == 1,
           let c = raw.first, let m = CommandPaletteModel.Mode(sigil: c) {
            model.mode = m
            inputText = ""           // Triggers a second onChange with raw=""
            model.query = ""
            model.runQuery(tab: tab, commands: commands)
            return
        }
        model.query = raw
        model.runQuery(tab: tab, commands: commands)
    }

    /// Two-tick delay so AppKit finishes whatever first-responder shuffling
    /// happens during the open animation before we ask for focus. Tested:
    /// without this, opening via the menu from a freshly-launched app
    /// often lands focus on nothing.
    private func refocusSoon() async {
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        queryFocused = true
    }

    private var indexBuilding: Bool {
        guard tab.index == nil else { return false }
        switch model.mode {
        case .fuzzy: return !model.query.isEmpty
        case .content, .symbol, .gitDirty: return true
        case .command: return false
        }
    }

    private var rows: [PaletteRowData] {
        if !model.commandHits.isEmpty { return model.commandHits.map { .command($0) } }
        if !model.contentHits.isEmpty { return model.contentHits.map { .content($0) } }
        if !model.symbolHits.isEmpty  { return model.symbolHits.map  { .symbol($0) } }
        return model.fileHits.map { .file($0) }
    }

    private var rowCount: Int { rows.count }

    private func activateSelected() {
        guard model.selectedIndex < rows.count else { return }
        onActivate(rows[model.selectedIndex])
    }
}

private struct PaletteLegend: View {
    @Environment(\.cairnTheme) private var theme

    var body: some View {
        HStack(spacing: 14) {
            chip(">", "Commands")
            chip("/", "Content")
            chip("@", "Symbols")
            chip("#", "Git dirty")
            Spacer()
            Text("↩ open  ↑↓ move  esc close")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.thinMaterial)
    }

    private func chip(_ sigil: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(sigil)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.accent)
                .frame(width: 14, height: 14)
                .background(RoundedRectangle(cornerRadius: 3).fill(theme.accentMuted))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
