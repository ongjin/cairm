import Foundation

struct HostMetadata: Codable, Hashable {
    var lastConnectedAt: Date?
    var pinned: Bool
    var hiddenFromSidebar: Bool
    var lastKnownState: String?          // "ok" | "error" | nil
}

final class HostMetadataStore {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.cairn.ssh.host-metadata")
    private var cache: [String: HostMetadata] = [:]

    init(url: URL? = nil) {
        if let url {
            self.fileURL = url
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = support.appendingPathComponent("Cairn", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("host-metadata.json")
        }
        load()
    }

    func metadata(for host: String) -> HostMetadata {
        queue.sync { cache[host] ?? HostMetadata(lastConnectedAt: nil, pinned: false, hiddenFromSidebar: false, lastKnownState: nil) }
    }

    func update(_ host: String, _ mutate: (inout HostMetadata) -> Void) {
        queue.sync {
            var m = cache[host] ?? HostMetadata(lastConnectedAt: nil, pinned: false, hiddenFromSidebar: false, lastKnownState: nil)
            mutate(&m)
            cache[host] = m
            persistLocked()
        }
    }

    func all() -> [String: HostMetadata] { queue.sync { cache } }

    private func load() {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL) else { return }
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            cache = (try? dec.decode([String: HostMetadata].self, from: data)) ?? [:]
        }
    }

    private func persistLocked() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(cache) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
