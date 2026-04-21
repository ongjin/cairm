import SwiftUI
import AppKit

/// SwiftUI wrapper over `NSVisualEffectView`. Plant as a `.background(...)`
/// or inside a `ZStack` to get macOS native blur (translucency + vibrancy).
///
/// Usage:
///   VStack { … }
///     .background(VisualEffectBlur(material: .hudWindow).ignoresSafeArea())
///
/// The `.active` state forces always-on blur regardless of window focus;
/// switch to `.followsWindowActiveState` if you want the system-default
/// desaturated-when-unfocused look.
struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = state
        v.isEmphasized = false
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}
