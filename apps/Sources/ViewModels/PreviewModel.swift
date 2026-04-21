import Foundation
import Observation

/// Preview state for the currently-focused URL. Owned by PreviewModel; read by
/// PreviewPaneView to pick the right renderer.
enum PreviewState: Equatable {
    case idle                       // no focus
    case loading                    // fetch in-flight
    case text(String)               // decoded text body (possibly truncated)
    case image(path: String)        // NSImage loaded lazily by the renderer
    case directory(childCount: Int) // summary for a selected folder
    case binary                     // binary / unsupported
    case failed(String)             // user-facing error string
}

/// Drives the detail pane.
///
/// `focus` is the URL the user currently wants previewed (driven by selection
/// in the file list). Setting `focus` kicks off an async fetch via the engine
/// and caches the result in an LRU (16 entries) so back-forth selection is
/// instant after the first visit.
///
/// The class is marked `@MainActor` so `focus`, `state`, and the cache are
/// mutated on the main thread consistently. FileManager I/O (directory
/// classification) runs off-main via `Task.detached`; the Rust `preview_text`
/// call is already detached inside `CairnEngine.previewText`.
@MainActor
@Observable
final class PreviewModel {
    static let cacheCapacity = 16

    var focus: URL? {
        didSet { handleFocusChange(from: oldValue) }
    }
    var state: PreviewState = .idle

    private let engine: CairnEngine

    /// Insertion-ordered (oldest → newest) for cheap LRU eviction.
    /// Keyed on standardizedFileURL.path so duplicate URL forms alias.
    private var cacheKeys: [String] = []
    private var cacheValues: [String: PreviewState] = [:]

    nonisolated init(engine: CairnEngine) {
        self.engine = engine
    }

    // MARK: - Cache

    /// Test/internal helper — directly poke a value into the cache without
    /// invoking the engine. Production callers set `focus` instead.
    func cache(state: PreviewState, for url: URL) {
        let key = url.standardizedFileURL.path
        if cacheValues[key] != nil {
            cacheKeys.removeAll { $0 == key }
        }
        cacheKeys.append(key)
        cacheValues[key] = state
        evictIfNeeded()
    }

    func cached(for url: URL) -> PreviewState? {
        cacheValues[url.standardizedFileURL.path]
    }

    private func evictIfNeeded() {
        while cacheKeys.count > Self.cacheCapacity {
            let dropped = cacheKeys.removeFirst()
            cacheValues.removeValue(forKey: dropped)
        }
    }

    // MARK: - Focus handling

    private func handleFocusChange(from previous: URL?) {
        guard let focus else {
            state = .idle
            return
        }
        if let hit = cached(for: focus) {
            state = hit
            return
        }
        state = .loading
        Task { [weak self] in
            await self?.loadPreview(for: focus)
        }
    }

    private func loadPreview(for url: URL) async {
        let next = await Self.compute(for: url, engine: engine)
        cache(state: next, for: url)
        // Only publish if the focus is still the same URL (user might have
        // selected something else while we were awaiting).
        if focus == url {
            state = next
        }
    }

    // MARK: - Pure classification (nonisolated so it can run off-main)

    private enum Classification {
        case directory(count: Int)
        case image
        case needsTextProbe
    }

    /// Decide which preview branch applies. Directory + image classification
    /// is sync FileManager I/O, hoisted onto a detached task so the main actor
    /// stays responsive. Text vs. binary is delegated to the Rust preview
    /// path (already detached inside CairnEngine.previewText).
    private nonisolated static func compute(for url: URL, engine: CairnEngine) async -> PreviewState {
        let path = url.standardizedFileURL.path

        let classification = await Task.detached(priority: .userInitiated) {
            classify(path: path, url: url)
        }.value

        switch classification {
        case .directory(let count):
            return .directory(childCount: count)
        case .image:
            return .image(path: path)
        case .needsTextProbe:
            do {
                let body = try await engine.previewText(url)
                return .text(body)
            } catch let e as PreviewError {
                switch e {
                case .Binary: return .binary
                case .NotFound: return .failed("File not found.")
                case .PermissionDenied: return .failed("Permission denied.")
                case .Io(let msg): return .failed("I/O error: \(msg.toString())")
                }
            } catch {
                return .failed(ErrorMessage.userFacing(error))
            }
        }
    }

    private nonisolated static func classify(path: String, url: URL) -> Classification {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
            let children = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
            return .directory(count: children.count)
        }
        let ext = url.pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "heic", "webp"].contains(ext) {
            return .image
        }
        return .needsTextProbe
    }
}
