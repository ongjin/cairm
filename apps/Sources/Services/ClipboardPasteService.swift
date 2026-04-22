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
    static func read(from pb: NSPasteboard) -> PasteContent? {
        // 1. File URLs — Finder's ⌘C stages this; Cairn drag-drop uses it too.
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           !urls.isEmpty {
            return .files(urls)
        }
        // 2. PNG — what macOS screencapture puts on the clipboard.
        if let data = pb.data(forType: .png) {
            return .image(data: data, ext: "png")
        }
        // 3. TIFF — "Copy Image" in some browsers. Normalize to PNG so the
        //    saved file is compact and universally recognized.
        if let tiff = pb.data(forType: .tiff),
           let png = tiffToPng(tiff) {
            return .image(data: png, ext: "png")
        }
        // 4. JPEG — some screenshot utilities stage this directly. Passthrough.
        let jpegType = NSPasteboard.PasteboardType("public.jpeg")
        if let data = pb.data(forType: jpegType) {
            return .image(data: data, ext: "jpg")
        }
        return nil
    }

    static func uniqueDestination(filename: String,
                                  in dir: URL,
                                  rule: CollisionRule) -> URL {
        let initial = dir.appendingPathComponent(filename)
        if !FileManager.default.fileExists(atPath: initial.path) {
            return initial
        }
        let (base, ext) = splitName(filename)
        var n = 2
        while true {
            let candidate: String
            switch rule {
            case .appendCopy:
                // n == 2 is the FIRST collision → unsuffixed " copy".
                // n == 3+ → " copy <n-1>" to match Finder ("foo copy", "foo copy 2").
                let suffix = (n == 2) ? "copy" : "copy \(n - 1)"
                candidate = ext.isEmpty ? "\(base) \(suffix)" : "\(base) \(suffix).\(ext)"
            case .appendNumber:
                // Straight numbering starting at 2 ("Untitled 2.png").
                candidate = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            }
            let url = dir.appendingPathComponent(candidate)
            if !FileManager.default.fileExists(atPath: url.path) {
                return url
            }
            n += 1
        }
    }

    /// Finder's filename/extension split. Returns extension without the leading dot.
    /// - Dotfiles (leading ".", no more dots): whole name is the base, no extension.
    /// - Composite extensions ("foo.tar.gz"): split on LAST dot only → ("foo.tar", "gz").
    /// - No dot: whole name is base, no extension.
    private static func splitName(_ filename: String) -> (base: String, ext: String) {
        if filename.hasPrefix(".") && !filename.dropFirst().contains(".") {
            return (filename, "")
        }
        if let dotIdx = filename.lastIndex(of: "."), dotIdx != filename.startIndex {
            let base = String(filename[..<dotIdx])
            let ext = String(filename[filename.index(after: dotIdx)...])
            return (base, ext)
        }
        return (filename, "")
    }

    static func tiffToPng(_ tiff: Data) -> Data? {
        guard let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    static func writeFileURLs(_ urls: [URL], to pb: NSPasteboard) { fatalError("stub") }
}
