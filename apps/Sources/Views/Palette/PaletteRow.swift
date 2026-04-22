import SwiftUI

enum PaletteRowData {
    case file(FileHit)
    case command(PaletteCommand)
    case content(ContentHit)
    case symbol(SymbolHit)
}

struct PaletteRow: View {
    let data: PaletteRowData
    let isSelected: Bool
    @Environment(\.cairnTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            icon
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(theme.bodyFont.weight(.medium))
                if let hint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let shortcut {
                Text(shortcut)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.15)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? theme.accentMuted : Color.clear)
    }

    private var icon: Image {
        switch data {
        case .file(let f): return Image(systemName: f.isDirectory ? "folder" : "doc")
        case .command(let c): return Image(systemName: c.iconSF)
        case .content: return Image(systemName: "text.magnifyingglass")
        case .symbol: return Image(systemName: "chevron.left.forwardslash.chevron.right")
        }
    }

    private var title: String {
        switch data {
        case .file(let f): return (f.pathRel as NSString).lastPathComponent
        case .command(let c): return c.label
        case .content(let h): return (h.pathRel as NSString).lastPathComponent
        case .symbol(let s): return s.name
        }
    }

    private var hint: String? {
        switch data {
        case .file(let f):
            let parent = (f.pathRel as NSString).deletingLastPathComponent
            return parent.isEmpty ? nil : parent
        case .command: return nil
        case .content(let h): return "\(h.pathRel):\(h.line) \u{00B7} \(h.preview)"
        case .symbol(let s): return "\(s.pathRel):\(s.line) \u{00B7} \(String(describing: s.kind))"
        }
    }

    private var shortcut: String? {
        if case .command(let c) = data { return c.shortcutHint }
        return nil
    }
}
