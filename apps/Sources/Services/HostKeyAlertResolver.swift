import AppKit

actor HostKeyAlertResolver {
    func resolve(host: String, port: UInt16, fingerprint: String, algorithm: String, knownState: String) async -> String {
        await MainActor.run { presentAlert(host: host, port: port, fingerprint: fingerprint, algorithm: algorithm, knownState: knownState) }
    }

    @MainActor
    private func presentAlert(host: String, port: UInt16, fingerprint: String, algorithm: String, knownState: String) -> String {
        let alert = NSAlert()
        switch knownState {
        case "mismatch":
            alert.alertStyle = .critical
            alert.messageText = "Host key CHANGED for \"\(host)\""
            alert.informativeText = "Offered: \(fingerprint)\n\nPossible MITM attack, or the host was reinstalled. Remove the old key in terminal: ssh-keygen -R \(host)"
            alert.addButton(withTitle: "Cancel")
            _ = alert.runModal()
            return "reject"
        case "not_found":
            alert.alertStyle = .warning
            alert.messageText = "New host key for \"\(host)\""
            alert.informativeText = "\(fingerprint)\nAlgorithm: \(algorithm)\n\nFirst connection to this host. Verify the fingerprint matches the server."
            alert.addButton(withTitle: "Accept & Save")
            alert.addButton(withTitle: "Accept Once")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn:  return "accept_save"
            case .alertSecondButtonReturn: return "accept"
            default:                       return "reject"
            }
        default:
            return "accept"
        }
    }
}
