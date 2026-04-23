import AppKit

actor PassphraseResolver {
    func resolve(keyPath: String) async -> String? {
        if let cached = KeychainPassphraseStore.load(for: keyPath) { return cached }
        return await MainActor.run { presentAlert(keyPath: keyPath) }
    }

    @MainActor
    private func presentAlert(keyPath: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "Unlock \((keyPath as NSString).abbreviatingWithTildeInPath)"
        alert.informativeText = "Enter the passphrase for this SSH key."
        alert.addButton(withTitle: "Unlock")
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
        if check.state == .on, !pass.isEmpty {
            KeychainPassphraseStore.save(pass, for: keyPath)
        }
        return pass.isEmpty ? nil : pass
    }
}
