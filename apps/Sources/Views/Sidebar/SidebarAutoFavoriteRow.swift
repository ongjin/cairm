import SwiftUI
import AppKit

/// Thin wrapper around `SidebarItemRow` for the auto-populated favorites
/// (Applications/Desktop/Documents/Downloads/Home). Tap navigates the active
/// tab to the bound URL; no pin/unpin affordance since these entries are
/// always present by definition.
struct SidebarAutoFavoriteRow: View {
    let icon: String
    let label: String
    let url: URL
    let isSelected: Bool
    let onActivate: () -> Void

    var body: some View {
        SidebarItemRow(icon: icon, label: label, tint: nil, isSelected: isSelected)
            .contentShape(Rectangle())
            .onTapGesture(perform: onActivate)
    }
}
