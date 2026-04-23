import Foundation

/// Appends a new Host block to ~/.ssh/config while preserving existing
/// file contents, trailing newline, and 0600 permissions. Never edits
/// or removes existing entries — v1 is append-only.
enum SshConfigWriter {
    struct Entry {
        var nickname: String
        var hostname: String?
        var port: UInt16?
        var user: String?
        var identityFile: String?
        var proxyCommand: String?
    }

    enum WriterError: Error { case invalidNickname, write(Error) }

    static func append(_ entry: Entry, to configURL: URL) throws {
        let trimmed = entry.nickname.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.contains(where: { " \t\n".contains($0) }) else {
            throw WriterError.invalidNickname
        }
        let fieldValues = [entry.hostname, entry.user, entry.identityFile, entry.proxyCommand].compactMap { $0 }
        guard !fieldValues.contains(where: { $0.contains("\n") || $0.contains("\r") }) else {
            throw WriterError.invalidNickname
        }

        let existing: String
        if FileManager.default.fileExists(atPath: configURL.path) {
            existing = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        } else {
            let dir = configURL.deletingLastPathComponent().path
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            existing = ""
        }

        var block = "\nHost \(trimmed)\n"
        if let h = entry.hostname { block += "    HostName \(h)\n" }
        if let p = entry.port, p != 22 { block += "    Port \(p)\n" }
        if let u = entry.user { block += "    User \(u)\n" }
        if let k = entry.identityFile { block += "    IdentityFile \(k)\n" }
        if let pc = entry.proxyCommand { block += "    ProxyCommand \(pc)\n" }

        let combined = existing + block

        do {
            try combined.write(to: configURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
        } catch {
            throw WriterError.write(error)
        }
    }
}
