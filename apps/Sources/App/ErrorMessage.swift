import Foundation

/// Translates Swift / Rust-bridged errors into short, user-facing strings at
/// UI presentation boundaries. Prefer this over `String(describing: error)`
/// which leaks enum case names (e.g., `PreviewError.Io("...")`) that aren't
/// useful to an end user. Debug logging (`NSLog`, `print`) should still use
/// the raw error description.
enum ErrorMessage {
    static func userFacing(_ error: Error) -> String {
        // swift-bridge Result<T, String> errors arrive typed as RustString;
        // NSError fallback prints "Cairn.RustString error 1." Extract the real text.
        if let rs = error as? RustString {
            return rs.toString()
        }
        if let localized = (error as? LocalizedError)?.errorDescription {
            return localized
        }
        let ns = error as NSError
        // Ignore the generic Cocoa fallback which looks like "RustString error 1".
        if !ns.localizedDescription.isEmpty,
           !ns.localizedDescription.contains("RustString error") {
            return ns.localizedDescription
        }
        return String(describing: error)
    }
}
