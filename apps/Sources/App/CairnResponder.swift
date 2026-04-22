// apps/Sources/App/CairnResponder.swift
import AppKit

/// Custom responder actions Cairn contributes to the standard Cocoa menu.
/// The protocol exists only so SwiftUI `CommandGroup` buttons and the
/// NSTableView subclass can share one `#selector` reference for the
/// non-standard ⌥⌘V "Paste Item Here" move action. Cocoa's built-in
/// `copy:` / `paste:` are reused unchanged.
@objc protocol CairnResponder: AnyObject {
    @objc func pasteItemHere(_ sender: Any?)
}
