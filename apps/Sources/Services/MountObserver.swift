import AppKit
import Observation

/// Observes macOS volume mount / unmount events and maintains an up-to-date list
/// of local mounted volume URLs. Used by SidebarModel to populate the Locations
/// section.
///
/// Subclassing NSObject lets us use `#selector` with NotificationCenter, and gives
/// us a deterministic `deinit` for observer teardown.
@Observable
final class MountObserver: NSObject {
    /// Current mounted local volumes (e.g. `/`, `/Volumes/ExternalDisk`).
    /// Populated synchronously from NSWorkspace at init; updated on mount/unmount
    /// notifications.
    private(set) var volumes: [URL]

    private let workspace: NSWorkspace

    override init() {
        self.workspace = NSWorkspace.shared
        self.volumes = MountObserver.currentVolumes()
        super.init()

        let nc = workspace.notificationCenter
        nc.addObserver(self,
                       selector: #selector(reload(_:)),
                       name: NSWorkspace.didMountNotification,
                       object: nil)
        nc.addObserver(self,
                       selector: #selector(reload(_:)),
                       name: NSWorkspace.didUnmountNotification,
                       object: nil)
    }

    deinit {
        workspace.notificationCenter.removeObserver(self)
    }

    @objc private func reload(_ note: Notification) {
        // Re-query on any mount change. List is always small (< 20 on a normal
        // workstation) so the full re-read is fine.
        volumes = MountObserver.currentVolumes()
    }

    private static func currentVolumes() -> [URL] {
        FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil,
                                               options: .skipHiddenVolumes) ?? []
    }
}
