import Foundation

enum ConnectionState: String, Codable, Hashable {
    case ok, error
}

struct HostMetadata: Codable, Hashable {
    var lastConnectedAt: Date?
    var pinned: Bool
    var hiddenFromSidebar: Bool
    var lastKnownState: ConnectionState?

    static let `default` = HostMetadata(lastConnectedAt: nil, pinned: false, hiddenFromSidebar: false, lastKnownState: nil)
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
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? {
               let dec = JSONDecoder()
               dec.dateDecodingStrategy = .iso8601
               return try dec.decode([String: HostMetadata].self, from: data)
           }() {
            cache = decoded
        }
    }

    func metadata(for host: String) -> HostMetadata {
        queue.sync { cache[host] ?? .default }
    }

    func update(_ host: String, _ mutate: (inout HostMetadata) -> Void) {
        queue.sync {
            var m = cache[host] ?? .default
            mutate(&m)
            cache[host] = m
            persistLocked()
        }
    }

    func all() -> [String: HostMetadata] { queue.sync { cache } }

    private func persistLocked() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(cache) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
