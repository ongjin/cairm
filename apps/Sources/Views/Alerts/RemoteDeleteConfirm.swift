import AppKit

enum RemoteDeleteConfirm {
    static var dontAskThisSession = false

    static func present(hostSummary: String, parent: String, names: [String], completion: @escaping (Bool) -> Void) {
        if dontAskThisSession { completion(true); return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete \(names.count) item\(names.count == 1 ? "" : "s") permanently?"
        let list = names.prefix(5).joined(separator: "\n \u{2022} ")
        let more = names.count > 5 ? "\n + \(names.count - 5) more" : ""
        alert.informativeText = "From \(hostSummary):\(parent)\n \u{2022} \(list)\(more)\n\nThis cannot be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        let check = NSButton(checkboxWithTitle: "Don\u{2019}t ask again for this session", target: nil, action: nil)
        alert.accessoryView = check

        let res = alert.runModal()
        if check.state == .on { dontAskThisSession = true }
        completion(res == .alertFirstButtonReturn)
    }
}
