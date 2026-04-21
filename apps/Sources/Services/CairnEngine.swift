import Foundation

// swift-bridge 0.1.59 doesn't emit `Error` conformance on generated enums, so
// adding it here lets `throws` work at every call site in the app. Scoped
// narrowly to avoid leaking into Rust-side assumptions.
extension WalkerError: Error {}
extension PreviewError: Error {}

/// Lightweight Swift wrapper around the Rust `Engine` exposed via swift-bridge.
///
/// Hides the opaque `FileListing` handle: Rust returns an indexed view, Swift
/// materialises a `[FileEntry]` once so view layers see a plain array.
///
/// Runs the FFI call on a detached Task so the UI thread stays responsive.
/// The caller is responsible for starting security-scoped access on any URL
/// that came from a user bookmark before invoking `listDirectory`.
@Observable
final class CairnEngine {
    private let rust: Engine

    init() {
        self.rust = new_engine()
    }

    /// Returns direct children of `url`. Requires prior start of security-scoped
    /// access if `url` originated from a stored bookmark.
    func listDirectory(_ url: URL) async throws -> [FileEntry] {
        let path = url.path
        return try await Task.detached { [rust] in
            let listing = try rust.list_directory(path)
            let n = Int(listing.len())
            var out: [FileEntry] = []
            out.reserveCapacity(n)
            for i in 0..<n {
                out.append(listing.entry(UInt(i)))
            }
            return out
        }.value
    }

    /// Returns up to 64 KB of decoded text content from `url`. Throws
    /// `PreviewError.Binary` on binary detection, `.NotFound`/`.PermissionDenied`
    /// on file-system errors. Caller is responsible for scoped access.
    func previewText(_ url: URL) async throws -> String {
        let path = url.path
        return try await Task.detached { [rust] in
            try rust.preview_text(path).toString()
        }.value
    }

    func setShowHidden(_ show: Bool) {
        rust.set_show_hidden(show)
    }
}
