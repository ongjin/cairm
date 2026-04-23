import Foundation
import Observation

@Observable
final class SshPoolService {
    private let pool: SshPoolBridge
    private let hostKeyResolver: HostKeyAlertResolver
    private let passphraseResolver: PassphraseResolver
    private let passwordResolver: PasswordResolver

    private(set) var sessions: [SshTarget: SessionState] = [:]

    /// Records which ssh_config alias opened each session. Needed because a
    /// ConnKey (user@host:port+config_hash) does not carry the alias, and
    /// comparing by substring of `resolvedSummary` breaks when the alias does
    /// not appear in the HostName (e.g. `app-cf` → `10.0.0.1`). Populated on
    /// `connect`, cleared on `disconnect` / `closeAll`.
    private(set) var aliasToTarget: [String: SshTarget] = [:]

    struct SessionState {
        enum Status { case connecting, active, idle, error(String) }
        var status: Status
        var lastActivity: Date
        var resolvedSummary: String
    }

    private var sftpHandles: [SshTarget: SftpHandleBridge] = [:]
    private var reaperTimer: Timer?

    init() {
        self.pool = ssh_pool_new()
        self.hostKeyResolver = HostKeyAlertResolver()
        self.passphraseResolver = PassphraseResolver()
        self.passwordResolver = PasswordResolver()
        startReaperTimer()
    }

    static func forTesting() -> SshPoolService { SshPoolService() }

    private func startReaperTimer() {
        reaperTimer?.invalidate()
        reaperTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshSessionStates()
        }
    }

    func connect(hostAlias: String, overrides: ConnectSpecOverrides = .init()) async throws -> SshTarget {
        let pool = self.pool
        let spec = ConnectSpecBridge(
            host_alias: RustString(hostAlias),
            user_override: overrides.user.map { RustString($0) },
            port_override: overrides.port,
            identity_file_override: overrides.identityFile.map { RustString($0) },
            proxy_command_override: overrides.proxyCommand.map { RustString($0) },
            password_override: RustString(overrides.password ?? "")
        )
        let hostKeyCallback = HostKeyCallback(resolver: self.hostKeyResolver)
        let passphraseCallback = PassphraseCallback(resolver: self.passphraseResolver)
        let passwordCallback = PasswordCallback(resolver: self.passwordResolver, alias: hostAlias)
        let key: ConnKeyBridge = try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try ssh_pool_connect(pool, spec, hostKeyCallback, passphraseCallback, passwordCallback)
                    cont.resume(returning: result)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
        let target = SshTarget(
            user: key.user.toString(),
            hostname: key.hostname.toString(),
            port: key.port,
            configHashHex: key.config_hash_hex.toString()
        )
        sessions[target] = SessionState(
            status: .active,
            lastActivity: Date(),
            resolvedSummary: "\(target.user)@\(target.hostname):\(target.port)"
        )
        aliasToTarget[hostAlias] = target
        return target
    }

    func sftpHandle(for target: SshTarget) async throws -> SftpHandleBridge {
        if let h = sftpHandles[target] { return h }
        let pool = self.pool
        let key = ConnKeyBridge(
            user: RustString(target.user),
            hostname: RustString(target.hostname),
            port: target.port,
            config_hash_hex: RustString(target.configHashHex)
        )
        let h = try await Task.detached(priority: .userInitiated) {
            try ssh_open_sftp(pool, key)
        }.value
        sftpHandles[target] = h
        sessions[target]?.lastActivity = Date()
        return h
    }

    func disconnect(_ target: SshTarget) {
        sftpHandles.removeValue(forKey: target)
        let key = ConnKeyBridge(
            user: RustString(target.user),
            hostname: RustString(target.hostname),
            port: target.port,
            config_hash_hex: RustString(target.configHashHex)
        )
        ssh_pool_disconnect(pool, key)
        sessions.removeValue(forKey: target)
        aliasToTarget = aliasToTarget.filter { $0.value != target }
    }

    func closeAll() {
        sftpHandles.removeAll()
        ssh_pool_close_all(pool)
        sessions.removeAll()
        aliasToTarget.removeAll()
    }

    private func refreshSessionStates() {
        // Mark sessions as idle when they haven't been used recently.
        let idleThreshold: TimeInterval = 300
        let now = Date()
        for target in sessions.keys {
            if let state = sessions[target], now.timeIntervalSince(state.lastActivity) > idleThreshold {
                sessions[target]?.status = .idle
            }
        }
    }
}

struct ConnectSpecOverrides {
    var user: String?
    var port: UInt16?
    var identityFile: String?
    var proxyCommand: String?
    /// Plain-text password. When set, the Rust pool tries password (with
    /// keyboard-interactive fallback) before any other method.
    var password: String?
}

// ---------------------------------------------------------------------------
// Swift callback wrappers — bridge the async Swift resolvers into blocking FFI
// ---------------------------------------------------------------------------

public final class HostKeyCallback {
    private let resolver: HostKeyAlertResolver

    init(resolver: HostKeyAlertResolver) {
        self.resolver = resolver
    }

    public func askHostKey(host: RustString, port: UInt16, offer: HostKeyOffer, state: RustString) -> String {
        let hostStr = host.toString()
        let fingerprint = offer.fingerprint.toString()
        let algorithm = offer.algorithm.toString()
        let stateStr = state.toString()
        let sem = DispatchSemaphore(value: 0)
        var result = "reject"
        Task {
            result = await resolver.resolve(
                host: hostStr,
                port: port,
                fingerprint: fingerprint,
                algorithm: algorithm,
                knownState: stateStr
            )
            sem.signal()
        }
        sem.wait()
        return result
    }
}

public final class PassphraseCallback {
    private let resolver: PassphraseResolver

    init(resolver: PassphraseResolver) {
        self.resolver = resolver
    }

    public func askPassphrase(key_path: RustString) -> String? {
        let path = key_path.toString()
        let sem = DispatchSemaphore(value: 0)
        var result: String?
        Task {
            result = await resolver.resolve(keyPath: path)
            sem.signal()
        }
        sem.wait()
        return result
    }
}

public final class PasswordCallback {
    private let resolver: PasswordResolver
    /// ssh_config nickname (or synthetic `user@host:port`) used as the Keychain
    /// key when the resolver saves a corrected password. Captured at
    /// connect-time since the resolver itself is shared across hosts.
    private let alias: String?

    init(resolver: PasswordResolver, alias: String?) {
        self.resolver = resolver
        self.alias = alias
    }

    public func askPassword(host: RustString, user: RustString) -> String? {
        let hostStr = host.toString()
        let userStr = user.toString()
        let aliasStr = self.alias
        let sem = DispatchSemaphore(value: 0)
        var result: String?
        Task {
            result = await resolver.resolve(host: hostStr, user: userStr, alias: aliasStr)
            sem.signal()
        }
        sem.wait()
        return result
    }
}
