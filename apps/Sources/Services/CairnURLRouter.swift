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
