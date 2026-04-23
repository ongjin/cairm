import SwiftUI

struct TransferHudChip: View {
    @Bindable var controller: TransferController
    @State private var popoverOpen: Bool = false
    @State private var pulseToken: UUID = UUID()

    var body: some View {
        Group {
            if controller.hasActive {
                chip
                    .onTapGesture { popoverOpen.toggle() }
                    .popover(isPresented: $popoverOpen, arrowEdge: .top) {
                        TransferPopoverView(controller: controller)
                    }
                    .onChange(of: controller.activeCount) { oldValue, newValue in
                        if newValue > oldValue { pulseToken = UUID() }
                    }
                    .modifier(PulseOnToken(token: pulseToken))
            }
        }
    }

    private var chip: some View {
        HStack(spacing: 5) {
            ProgressView().controlSize(.mini).tint(Color(red: 0.55, green: 0.85, blue: 0.73))
            Text("↕ \(controller.activeCount)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(red: 0.72, green: 0.94, blue: 0.85))
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(red: 0.55, green: 0.85, blue: 0.73).opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color(red: 0.55, green: 0.85, blue: 0.73).opacity(0.35))
                )
        )
    }
}

struct PulseOnToken: ViewModifier {
    let token: UUID
    @State private var scale: CGFloat = 1.0
    func body(content: Content) -> some View {
        content.scaleEffect(scale)
            .onChange(of: token) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) { scale = 1.15 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeIn(duration: 0.3)) { scale = 1.0 }
                }
            }
    }
}
