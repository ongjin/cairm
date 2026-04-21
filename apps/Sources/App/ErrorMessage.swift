import Foundation

/// Translates Swift / Rust-bridged errors into short, user-facing strings at
/// UI presentation boundaries. Prefer this over `String(describing: error)`
/// which leaks enum case names (e.g., `PreviewError.Io("...")`) that aren't
/// useful to an end user. Debug logging (`NSLog`, `print`) should still use
/// the raw error description.
enum ErrorMessage {
    static func userFacing(_ error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription {
            return localized
        }
        let ns = error as NSError
        if !ns.localizedDescription.isEmpty {
            return ns.localizedDescription
        }
        return String(describing: error)
    }
}
