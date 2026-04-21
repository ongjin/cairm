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
        sidebarTint: Color(hue: 0.62, saturation: 0.08, brightness: 0.14),
        panelTint:   Color(hue: 0.62, saturation: 0.06, brightness: 0.12),
        text:          Color(white: 0.93),
        textSecondary: Color(white: 0.60),
        textTertiary:  Color(white: 0.42),
        accent:        Color(red: 0.04, green: 0.52, blue: 1.00),   // #0A84FF
        accentMuted:   Color(red: 0.04, green: 0.52, blue: 1.00, opacity: 0.22),
        selectionFg:   .white,
        cornerRadius: 6,
        rowHeight: 24,
        sidebarRowHeight: 22,
        panelPadding: EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10),
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
