import SwiftUI
import AppKit

/// Design tokens for Cairn's visual theme.
///
/// Phase 1 ships a single `.glass` instance (Glass Blue). The theme switcher
/// is Phase 3. Consumers read via `@Environment(\.cairnTheme)`; the default
/// value is `.glass`, so tests and previews work without explicit injection.
struct CairnTheme: Equatable {
    let id: String
    let displayName: String

    // Window / panels
    let windowMaterial: NSVisualEffectView.Material
    let sidebarTint: Color
    let panelTint: Color

    // Text
    let text: Color
    let textSecondary: Color
    let textTertiary: Color

    // Accent
    let accent: Color
    let accentMuted: Color
    let selectionFg: Color

    // Geometry
    let cornerRadius: CGFloat
    let rowHeight: CGFloat
    let sidebarRowHeight: CGFloat
    let panelPadding: EdgeInsets

    // Typography
    let bodyFont: Font
    let monoFont: Font
    let headerFont: Font

    // Layout (Phase 1 엔 threePane 하나)
    let layout: LayoutVariant
}

enum LayoutVariant { case threePane, paletteFirst }

extension CairnTheme {
    static let glass = CairnTheme(
        id: "glass",
        displayName: "Glass (Blue)",
        windowMaterial: .hudWindow,
        // Clearly blue, more saturated, higher brightness so the tint
        // actually reads as a colour rather than grey.
        sidebarTint: Color(hue: 0.60, saturation: 0.42, brightness: 0.45, opacity: 0.55),
        panelTint:   Color(hue: 0.60, saturation: 0.30, brightness: 0.42, opacity: 0.20),
        text:          Color(white: 0.97),
        textSecondary: Color(white: 0.78),
        textTertiary:  Color(white: 0.56),
        accent:        Color(red: 0.10, green: 0.55, blue: 1.00),
        accentMuted:   Color(red: 0.10, green: 0.55, blue: 1.00, opacity: 0.30),
        selectionFg:   .white,
        cornerRadius: 8,
        rowHeight: 26,
        sidebarRowHeight: 24,
        panelPadding: EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12),
        bodyFont:   .system(size: 12),
        monoFont:   .system(size: 11, design: .monospaced),
        headerFont: .system(size: 10, weight: .semibold),
        layout: .threePane
    )
}

// MARK: - Environment

private struct CairnThemeKey: EnvironmentKey {
    static let defaultValue: CairnTheme = .glass
}

extension EnvironmentValues {
    var cairnTheme: CairnTheme {
        get { self[CairnThemeKey.self] }
        set { self[CairnThemeKey.self] = newValue }
    }
}
