import Foundation

@Observable
final class SshConfigService {
    private(set) var configuredHosts: [String] = []
    private let metadata: HostMetadataStore
    private var watcher: ConfigFileWatcher?

    init(metadata: HostMetadataStore) {
        self.metadata = metadata
        reload()
        self.watcher = ConfigFileWatcher { [weak self] in
            Task { @MainActor in self?.reload() }
        }
    }

    func reload() {
        configuredHosts = ssh_pool_list_configured_hosts().map { $0.as_str().toString() }
    }

    func appendHost(_ entry: SshConfigWriter.Entry) throws {
        let home = ProcessInfo.processInfo.environment["HOME"]!
        let url = URL(fileURLWithPath: "\(home)/.ssh/config")
        try SshConfigWriter.append(entry, to: url)
        reload()
    }

    func metadataFor(_ host: String) -> HostMetadata { metadata.metadata(for: host) }

    func touch(_ host: String, state: String?) {
        metadata.update(host) {
            $0.lastConnectedAt = Date()
            if let state { $0.lastKnownState = state }
        }
    }
}
