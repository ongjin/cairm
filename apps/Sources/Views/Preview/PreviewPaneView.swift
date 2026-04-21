import SwiftUI
import Foundation

/// Detail-pane root. Shows an optional metadata header + the renderer matching
/// the current PreviewState. The header is suppressed in .idle to keep the
/// empty state visually quiet.
struct PreviewPaneView: View {
    @Bindable var preview: PreviewModel

    var body: some View {
        VStack(spacing: 0) {
            if let url = preview.focus, !isIdle {
                header(for: url)
                Divider()
            }
            renderer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        }
    }

    private func header(for url: URL) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(url.lastPathComponent)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(url.deletingLastPathComponent().path)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
            if let size = fileSize(for: url) {
                Text(size)
                    .font(.system(size: 10))
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
