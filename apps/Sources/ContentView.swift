import SwiftUI

struct ContentView: View {
    // Rust에서 받아오는 초기 인사말. Phase 0 검증 지점.
    @State private var greeting: String = "Loading..."

    var body: some View {
        ZStack {
            // Theme B의 미니 프리뷰 — 방사형 컬러 그라디언트 + 다크 베이스
            LinearGradient(
                colors: [.teal.opacity(0.4), .indigo.opacity(0.5), .pink.opacity(0.35)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                Text("🏔️")
                    .font(.system(size: 64))
                Text(greeting)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Phase 0 — Foundation")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(40)
        }
        .task {
            greeting = greet().toString()
        }
    }
}
