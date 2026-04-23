import Foundation

/// Pure async helper that walks `Untitled` → `Untitled 2` → `Untitled 3` …
/// until `probe(candidate)` reports "not present". Split out of the
/// remote-paste path so the naming loop is unit-testable without an
/// actual SFTP handle — the clipboard/paste surface is already a known
/// data-loss hazard (screenshots overwrite silently) so the probe loop
/// gets its own tests.
///
/// `probe` returns `true` iff the candidate already exists on the remote.
/// Callers pass `{ path in (try? await provider.stat(path)) != nil }` in
/// production, and a synchronous fake in tests.
enum RemoteNameResolver {
    static func uniqueRemotePath(
        base: String,
        ext: String,
        in dir: FSPath,
        probe: (FSPath) async -> Bool
    ) async -> FSPath {
        let first = dir.appending(ext.isEmpty ? base : "\(base).\(ext)")
        if await probe(first) == false { return first }
        var n = 2
        while true {
            let name = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            let candidate = dir.appending(name)
            if await probe(candidate) == false { return candidate }
            n += 1
        }
    }
}
