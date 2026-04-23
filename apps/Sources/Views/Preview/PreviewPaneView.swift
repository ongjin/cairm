import SwiftUI
import Foundation

/// Detail-pane root. Shows an optional metadata header + the renderer matching
/// the current PreviewState. The header is suppressed in .idle to keep the
/// empty state visually quiet.
struct PreviewPaneView: View {
    @Bindable var preview: PreviewModel
    @Environment(\.cairnTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            if let url = preview.focus, !isIdle {
                header(for: url)
                Divider()
            }
            renderer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                VisualEffectBlur(material: .contentBackground)
                theme.panelTint.opacity(0.4)
            }
            .ignoresSafeArea()
        }
    }

    private var isIdle: Bool {
        if case .idle = preview.state { return true }
        return false
    }

    @ViewBuilder
    private var renderer: some View {
        switch preview.state {
        case .idle:
            IdlePreview()
        case .loading:
            LoadingPreview()
        case .text(let s):
            TextPreview(s)
        case .image(let path):
            ImagePreview(path: path)
        case .directory(let n):
            DirectoryPreview(childCount: n)
        case .binary:
            BinaryPreview()
        case .failed(let m):
            FailedPreview(message: m)
        case .pressSpaceForFullPreview:
            VStack(spacing: 8) {
                Image(systemName: "space")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("Press Space to preview")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(for url: URL) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(url.lastPathComponent)
                .font(theme.bodyFont.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(url.deletingLastPathComponent().path)
                .font(theme.headerFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
            // Size row is only shown for local focuses. Remote
            // focuses synthesize a local `URL(fileURLWithPath:)` for
            // display; feeding that into `FileManager` would either
            // silently return the local-disk size for collision
            // paths (`/etc/hosts`, `/var/log/...`) or `nil` — both
            // wrong. Plumbing true remote size would need a
            // dedicated stat round-trip on selection; defer that and
            // just suppress the line.
            if preview.remoteFocus == nil, let size = fileSize(for: url) {
                Text(size)
                    .font(theme.headerFont)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fileSize(for url: URL) -> String? {
        guard let n = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int else {
            return nil
        }
        return ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    }
}
