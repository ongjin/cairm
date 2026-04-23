import AppKit

/// Prompts the user for an SSH login password when the preset (from the
/// Connect sheet or a Keychain lookup) is rejected by the server. Offers
/// "Remember in Keychain" so a corrected password persists across reconnects.
actor PasswordResolver {
    /// Called by the Rust pool on auth rejection. `alias` is the ssh_config
    /// nickname when we have one (so the saved password keys back to the same
    /// entry that was pre-filled), otherwise a synthetic `user@host:port`.
    func resolve(host: String, user: String, alias: String?) async -> String? {
        await MainActor.run { presentAlert(host: host, user: user, alias: alias) }
    }

    @MainActor
    private func presentAlert(host: String, user: String, alias: String?) -> String? {
        let alert = NSAlert()
        alert.messageText = "Password for \(user)@\(host)"
        alert.informativeText = "The previous password was rejected. Enter the current password to continue."
        alert.addButton(withTitle: "Authenticate")
        alert.addButton(withTitle: "Cancel")

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 22))
        let check = NSButton(checkboxWithTitle: "Remember in Keychain", target: nil, action: nil)
        check.state = .on

        let stack = NSStackView(views: [field, check])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 260, height: 52)
        alert.accessoryView = stack

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let pass = field.stringValue
        if check.state == .on, !pass.isEmpty, let alias {
            KeychainPasswordStore.save(pass, for: alias)
        }
        return pass.isEmpty ? nil : pass
    }
}
