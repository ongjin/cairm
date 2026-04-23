import Foundation
import Observation

/// Composes the two "synthetic" sidebar sections whose content is not
/// bookmark-backed: iCloud Drive (a single well-known path) and Locations
/// (computer root + live mounted volumes).
///
/// Pinned is read directly from BookmarkStore by SidebarView — no reason to
/// mirror it here.
@Observable
final class SidebarModel {
    /// Well-known path to iCloud Drive's local mirror. Works without the iCloud
    /// entitlement because we only check disk existence; navigating in is a
    /// regular file URL access. Users without iCloud signed in won't have this
    /// directory, and we silently hide the section.
    static let iCloudDrivePath: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")

    /// Nil when iCloud Drive isn't set up on this machine.
    private(set) var iCloudURL: URL?

    /// Computer root (`/`) followed by currently-mounted local volumes in the
    /// order NSWorkspace reports them.
    private(set) var locations: [URL]

    private let mountObserver: MountObserver
    /// Observation token retained to receive mount changes. We track through
    /// @Observable's implicit observation rather than an explicit subscriber,
    /// keyed on the observer's `volumes` property.
    private var observationTask: Task<Void, Never>?

    init(mountObserver: MountObserver) {
        self.mountObserver = mountObserver
        self.iCloudURL = FileManager.default.fileExists(atPath: Self.iCloudDrivePath.path)
            ? Self.iCloudDrivePath
            : nil
        self.locations = Self.composeLocations(from: mountObserver.volumes)

        // Recompute `locations` whenever observer.volumes changes.
        // @Observable's withObservationTracking requires manual re-arming
        // after each fire — a simple long-running task loops for us.
        self.observationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await withCheckedContinuation { cont in
                    withObservationTracking {
                        _ = self?.mountObserver.volumes
                    } onChange: {
                        cont.resume()
                    }
                }
                guard let self else { return }
                self.locations = Self.composeLocations(from: self.mountObserver.volumes)
            }
        }
    }

    deinit {
        observationTask?.cancel()
    }

    private static func composeLocations(from volumes: [URL]) -> [URL] {
        var out: [URL] = [URL(fileURLWithPath: "/")]
        for v in volumes where v.path != "/" {
            out.append(v)
        }
        return out
    }
}

extension SidebarModel {
    struct RemoteHostItem: Identifiable, Hashable {
        let id: String              // host nickname
        let displaySummary: String
        let state: State
        let pinned: Bool
        let lastConnectedAt: Date?
        enum State: String { case connected, idle, error, disconnected }
    }

    @MainActor
    func remoteHostItems(from svc: SshConfigService, pool: SshPoolService) -> [RemoteHostItem] {
        svc.configuredHosts.compactMap { name in
            let meta = svc.metadataFor(name)
            if meta.hiddenFromSidebar { return nil }
            // Match by alias-tracked target, not by substring of the resolved
            // summary — `app-cf` → HostName `10.0.0.1` wouldn't match otherwise.
            let state: RemoteHostItem.State
            if let target = pool.aliasToTarget[name], pool.sessions[target] != nil {
                state = .connected
            } else {
                state = .disconnected
            }
            return RemoteHostItem(
                id: name,
                displaySummary: meta.lastConnectedAt.map { "last connected \(relative($0))" } ?? "",
                state: state,
                pinned: meta.pinned,
                lastConnectedAt: meta.lastConnectedAt
            )
        }.sorted {
            if $0.pinned != $1.pinned { return $0.pinned }
            return ($0.lastConnectedAt ?? .distantPast) > ($1.lastConnectedAt ?? .distantPast)
        }
    }

    private func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: Date())
    }
}
