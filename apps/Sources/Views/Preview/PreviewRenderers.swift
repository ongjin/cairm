import SwiftUI
import AppKit

// MARK: - Idle

struct IdlePreview: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("Select a file to preview")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Loading

struct LoadingPreview: View {
    var body: some View {
        ProgressView().controlSize(.small)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Text

struct TextPreview: View {
    let body_: String

    init(_ text: String) { self.body_ = text }

    var body: some View {
        ScrollView {
            Text(body_)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
    }
}

// MARK: - Image

/// Async-loads NSImage off the main thread so large files don't stall UI.
/// Scales proportional fit inside 256pt content box.
struct ImagePreview: View {
    let path: String

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: 256, maxHeight: 256)
            } else {
                LoadingPreview()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: path) {
            let p = path
            let decoded = await Task.detached { NSImage(contentsOf: URL(fileURLWithPath: p)) }.value
            image = decoded
        }
    }
}

// MARK: - Directory

struct DirectoryPreview: View {
    let childCount: Int
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.system(size: 32))
                .foregroundStyle(.blue)
            Text(childCount == 1 ? "1 item" : "\(childCount) items")
                .font(.system(size: 12))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Binary / Failed

struct BinaryPreview: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "lock.doc")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("Preview not available (binary file)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FailedPreview: View {
    let message: String
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
