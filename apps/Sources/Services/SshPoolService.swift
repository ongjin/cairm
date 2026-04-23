import Foundation
import Observation

@Observable
final class SshPoolService {
    private let pool: SshPoolBridge
    private let hostKeyResolver: HostKeyAlertResolver
    private let passphraseResolver: PassphraseResolver

    private(set) var sessions: [SshTarget: SessionState] = [:]

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
            proxy_command_override: overrides.proxyCommand.map { RustString($0) }
        )
        let key = try await Task.detached(priority: .userInitiated) {
            try ssh_pool_connect(pool, spec)
        }.value
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
    }

    func closeAll() {
        sftpHandles.removeAll()
        ssh_pool_close_all(pool)
        sessions.removeAll()
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
}
