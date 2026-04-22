import AppKit

/// Direction of a paste: copy leaves the source intact, move removes it.
/// Used by both the keyboard shortcut dispatch (⌘V vs ⌥⌘V) and the menu.
enum PasteOp {
    case copy
    case move
}

/// What the pasteboard contains, in the priority Cairn cares about. File URLs
/// always win over image data (matches Finder's behavior when a user drags an
/// image out of an app into Finder — Finder pastes the file, not the bytes).
enum PasteContent {
    case files([URL])
    /// Raw bytes ready to write to disk with the given extension.
    case image(data: Data, ext: String)
}

/// Naming policy when the destination already exists.
enum CollisionRule {
    /// Finder's file-copy style: "foo.txt" → "foo copy.txt" → "foo copy 2.txt".
    case appendCopy
    /// Finder's new-folder / screenshot style: "Untitled.png" → "Untitled 2.png".
    case appendNumber
}

/// Pure helpers for moving data between NSPasteboard and the filesystem.
/// No AppKit view state, no main-thread requirements — everything here is safe
/// to unit test in isolation.
enum ClipboardPasteService {
    // Implementations added in later tasks.
    static func read(from pb: NSPasteboard) -> PasteContent? { fatalError("stub") }

    static func uniqueDestination(filename: String,
                                  in dir: URL,
                                  rule: CollisionRule) -> URL { fatalError("stub") }

    static func tiffToPng(_ tiff: Data) -> Data? { fatalError("stub") }

    static func writeFileURLs(_ urls: [URL], to pb: NSPasteboard) { fatalError("stub") }
}
