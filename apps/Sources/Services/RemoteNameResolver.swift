import Foundation

/// Pure async helper that walks `Untitled` → `Untitled 2` → `Untitled 3` …
/// until `probe(candidate)` reports "not present". Split out of the
/// remote-paste path so the naming loop is unit-testable without an
/// actual SFTP handle — the clipboard/paste surface is already a known
/// data-loss hazard (screenshots overwrite silently) so the probe loop
/// gets its own tests.
///
/// `probe` returns `true` iff the candidate already exists and MUST throw
/// on any non-"not-found" error (transport, permission, protocol). The
/// resolver propagates that throw so the caller can abort the paste — if
/// we converted unknown errors to "doesn't exist", the very next
/// `uploadFromLocal` would truncate an existing remote file under a
/// flaky connection.
enum RemoteNameResolver {
    static func uniqueRemotePath(
        base: String,
        ext: String,
        in dir: FSPath,
        probe: (FSPath) async throws -> Bool
    ) async throws -> FSPath {
        let first = dir.appending(ext.isEmpty ? base : "\(base).\(ext)")
        if try await probe(first) == false { return first }
        var n = 2
        while true {
            let name = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            let candidate = dir.appending(name)
            if try await probe(candidate) == false { return candidate }
            n += 1
        }
    }
}
