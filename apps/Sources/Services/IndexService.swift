import Foundation
import Observation

/// Swift wrapper around the Rust `IndexHandle`. One instance per Tab.
/// Owns the handle lifecycle via open/close.
@Observable
final class IndexService {
    private let handle: UInt64
    let root: URL

    init?(root: URL) {
        self.root = root
        let id = ffi_index_open(root.path)
        guard id != 0 else { return nil }
        self.handle = id
    }

    deinit {
        ffi_index_close(handle)
    }

    func queryFuzzy(_ query: String, limit: Int = 50) -> [FileHit] {
        let list = ffi_index_query_fuzzy(handle, query, UInt32(limit))
        let n = list.len()
        var out: [FileHit] = []
        out.reserveCapacity(Int(n))
        for i in 0..<n {
            let h = list.at(i)
            out.append(FileHit(pathRel: h.path_rel.toString(),
                               score: Int(h.score),
                               isDirectory: h.kind_raw == 1))
        }
        return out
    }

    func querySymbols(_ query: String, limit: Int = 50) -> [SymbolHit] {
        let list = ffi_index_query_symbols(handle, query, UInt32(limit))
        let n = list.len()
        var out: [SymbolHit] = []
        out.reserveCapacity(Int(n))
        for i in 0..<n {
            let h = list.at(i)
            out.append(SymbolHit(pathRel: h.path_rel.toString(), name: h.name.toString(),
                                 kind: SymbolKind(rawByte: h.kind_raw), line: Int(h.line)))
        }
        return out
    }

    func queryGitDirty() -> [FileHit] {
        let list = ffi_index_query_git_dirty(handle)
        let n = list.len()
        var out: [FileHit] = []
        out.reserveCapacity(Int(n))
        for i in 0..<n {
            let h = list.at(i)
            // Modified files are by definition regular — git can't track an
            // empty directory, so isDirectory is always false here.
            out.append(FileHit(pathRel: h.path_rel.toString(), score: 0, isDirectory: false))
        }
        return out
    }

    func startContent(pattern: String, isRegex: Bool = false) -> ContentSearchSession? {
        let sid = ffi_content_start(handle, pattern, isRegex)
        guard sid != 0 else { return nil }
        return ContentSearchSession(sessionID: sid)
    }
}

struct FileHit: Identifiable, Hashable {
    let pathRel: String
    let score: Int
    /// True when the indexed entry is a directory. Drives the folder vs
    /// document icon in PaletteRow so users can tell at a glance whether
    /// hitting Enter will navigate or open a file.
    let isDirectory: Bool
    var id: String { pathRel }

    init(pathRel: String, score: Int, isDirectory: Bool = false) {
        self.pathRel = pathRel
        self.score = score
        self.isDirectory = isDirectory
    }
}

struct SymbolHit: Identifiable, Hashable {
    let pathRel: String
    let name: String
    let kind: SymbolKind
    let line: Int
    var id: String { "\(pathRel):\(line):\(name)" }
}

enum SymbolKind: UInt8 {
    case klass = 0, strct = 1, enm = 2, function = 3, method = 4, variable = 5, constant = 6, interface = 7, unknown = 255
    init(rawByte: UInt8) { self = SymbolKind(rawValue: rawByte) ?? .unknown }
}

/// Polling-based stream for content search results.
final class ContentSearchSession {
    /// Hard cap on `results` to keep memory and SwiftUI render cost bounded
    /// for pathological queries on huge repos. The palette/search UI shows
    /// at most a few hundred rows at a time, so 5K is a generous ceiling
    /// that still prevents runaway growth (tens of thousands of hits).
    /// Reaching the cap silently auto-cancels the session — callers see the
    /// session stop producing new results, same as a natural completion.
    static let maxResults = 5000

    private let sessionID: UInt64
    private(set) var results: [ContentHit] = []
    /// Set once `cancel()` has fired the FFI so `deinit` doesn't fire it
    /// again. The Rust side currently treats a missing-session cancel as a
    /// no-op, but a double-call is wasteful and would become a latent bug
    /// the moment cancellation gains side effects.
    private var cancelled: Bool = false

    init(sessionID: UInt64) { self.sessionID = sessionID }
    deinit {
        if !cancelled { ffi_content_cancel(sessionID) }
    }

    func poll(max: Int = 50) -> [ContentHit] {
        // Stop polling entirely once we've hit the cap — there's no point
        // pulling more hits we'd just throw away.
        if cancelled || results.count >= Self.maxResults { return [] }
        let list = ffi_content_poll(sessionID, UInt32(max))
        let n = list.len()
        var mapped: [ContentHit] = []
        mapped.reserveCapacity(Int(n))
        for i in 0..<n {
            let h = list.at(i)
            mapped.append(ContentHit(pathRel: h.path_rel.toString(), line: Int(h.line), preview: h.preview.toString()))
        }
        results.append(contentsOf: mapped)
        if results.count >= Self.maxResults {
            // Trim any overshoot from the final batch, then auto-cancel so
            // the Rust worker stops producing.
            if results.count > Self.maxResults {
                results.removeLast(results.count - Self.maxResults)
            }
            cancel()
        }
        return mapped
    }

    func cancel() {
        guard !cancelled else { return }
        cancelled = true
        ffi_content_cancel(sessionID)
    }
}

struct ContentHit: Identifiable, Hashable {
    let pathRel: String
    let line: Int
    let preview: String
    var id: String { "\(pathRel):\(line)" }
}
