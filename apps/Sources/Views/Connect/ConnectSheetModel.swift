import Foundation
import Observation

@Observable
final class ConnectSheetModel: Identifiable {
    let id = UUID()
    var server: String = ""
    var port: String = "22"
    var path: String = "~"
    enum AuthMode: String { case agent, keyFile, password }
    var authMode: AuthMode = .agent
    var keyFile: String = "~/.ssh/id_ed25519"
    var password: String = ""
    var proxyCommand: String = ""
    var showAdvanced: Bool = false
    var saveToConfig: Bool = false
    var nickname: String = ""
    var connecting: Bool = false
    var error: String? = nil

    func resolveUserHost() -> (user: String?, host: String) {
        if let at = server.firstIndex(of: "@") {
            return (String(server[server.startIndex..<at]), String(server[server.index(after: at)...]))
        } else {
            return (nil, server)
        }
    }

    func acceptURL(_ url: String) {
        guard let parsed = URLComponents(string: url), parsed.scheme == "ssh" else { return }
        if let u = parsed.user, let h = parsed.host {
            server = "\(u)@\(h)"
        } else if let h = parsed.host {
            server = h
        }
        if let p = parsed.port { port = String(p) }
        if !parsed.path.isEmpty { path = parsed.path }
    }
}
