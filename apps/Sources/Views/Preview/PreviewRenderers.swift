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

/// Wraps an `NSTextView` so previewing 30-100 KB of source is fast. SwiftUI
/// `Text` with `.textSelection(.enabled)` doesn't virtualize — it lays out
/// the whole string once and tracks per-character selection metadata, which
/// runs hundreds of ms for files in this size range. NSTextView's layout
/// manager only renders visible glyphs, so scrolling and initial display
/// are effectively constant-time regardless of body length.
struct TextPreview: NSViewRepresentable {
    let bodyText: String

    init(_ text: String) { self.bodyText = text }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.isEditable = false
        tv.isRichText = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        // Disable auto-substitutions that NSTextView does by default — these
        // are just CPU work for read-only preview content.
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.string = bodyText
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        // Only rewrite when the content actually changed — assigning .string
        // is the expensive part on big bodies.
        if tv.string != bodyText {
            tv.string = bodyText
            tv.scroll(NSPoint.zero)
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
            // Reset immediately so stale image doesn't linger during decode.
            image = nil
            let p = path
            let decoded = await Task.detached { NSImage(contentsOf: URL(fileURLWithPath: p)) }.value
            image = decoded
        }
    }
}

// MARK: - Directory

struct DirectoryPreview: View {
    /// `nil` on remote selections where we deliberately skip the
    /// listing round-trip — show a neutral "Directory" label instead
    /// of a misleading "0 items".
    let childCount: Int?
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.system(size: 32))
                .foregroundStyle(.blue)
            Text(label)
                .font(.system(size: 12))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var label: String {
        guard let n = childCount else { return "Directory" }
        return n == 1 ? "1 item" : "\(n) items"
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
