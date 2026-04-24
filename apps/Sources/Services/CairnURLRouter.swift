import Foundation

enum CairnOpenRequest: Equatable {
    case openLocal(URL)
    case openRemote(alias: String, path: String)
}

enum CairnURLError: Error, LocalizedError {
    case malformed(String)

    var errorDescription: String? {
        if case .malformed(let message) = self {
            return "cairn URL: \(message)"
        }
        return nil
    }
}

enum CairnURLRouter {
    /// Parses a cairn:// URL into a CairnOpenRequest. Supported shapes:
    ///   cairn://open?path=/abs/path
    ///   cairn://remote?host=<ssh_config alias>&path=/abs/path
    static func parse(_ url: URL) throws -> CairnOpenRequest {
        guard url.scheme == "cairn" else {
            throw CairnURLError.malformed("not a cairn URL: \(url)")
        }
        let host = url.host ?? ""
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        switch host {
        case "open":
            guard let path = queryItems.first(where: { $0.name == "path" })?.value, !path.isEmpty else {
                throw CairnURLError.malformed("missing path")
            }
            return .openLocal(URL(fileURLWithPath: path))
        case "remote":
            guard let alias = queryItems.first(where: { $0.name == "host" })?.value, !alias.isEmpty else {
                throw CairnURLError.malformed("missing host")
            }
            guard let path = queryItems.first(where: { $0.name == "path" })?.value, !path.isEmpty else {
                throw CairnURLError.malformed("missing path")
            }
            return .openRemote(alias: alias, path: path)
        default:
            throw CairnURLError.malformed("unknown action '\(host)'")
        }
    }
}

extension CairnURLRouter {
    @MainActor
    static func dispatch(_ request: CairnOpenRequest, in app: AppModel, activeScene scene: WindowSceneModel) {
        switch request {
        case .openLocal(let url):
            scene.newTab(initialURL: url)
        case .openRemote(let alias, let path):
            guard app.sshConfig.configuredHosts.contains(alias) else {
                let model = ConnectSheetModel()
                model.server = alias
                scene.connectSheetModel = model
                return
            }
            let placeholder = scene.newEstablishingTab(alias: alias)
            Task { @MainActor in
                do {
                    let target = try await app.ssh.connect(hostAlias: alias, overrides: ConnectSpecOverrides())
                    let provider = SshFileSystemProvider(pool: app.ssh, target: target, supportsServerSideCopy: false)
                    let initial = FSPath(provider: .ssh(target), path: path)
                    placeholder.upgradeToRemote(path: initial, provider: provider)
                    await placeholder.folder.load(initial, via: provider)
                    placeholder.connectionPhase = .connected
                } catch {
                    scene.closeTab(placeholder.id)
                    let model = ConnectSheetModel()
                    model.server = alias
                    model.error = ErrorMessage.userFacing(error)
                    scene.connectSheetModel = model
                }
            }
        }
    }
}
