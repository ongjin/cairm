import SwiftUI

/// Path segments for the current folder, rendered as clickable buttons.
/// Lives inside ContentView's toolbar. "Computer" slash is represented as a
/// single leading "/" segment.
struct BreadcrumbBar: View {
    @Bindable var app: AppModel

    var body: some View {
        if let current = app.currentFolder {
            HStack(spacing: 2) {
                ForEach(Array(segments(for: current).enumerated()), id: \.offset) { pair in
                    let (i, seg) = pair
                    Button(seg.label) { app.navigateUnscoped(to: seg.url) }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(i == segments(for: current).count - 1 ? Color.primary : Color.secondary)
                    if i < segments(for: current).count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 6)
        }
    }

    private func segments(for url: URL) -> [(label: String, url: URL)] {
        var out: [(String, URL)] = []
        let components = url.standardizedFileURL.pathComponents
        var accum = URL(fileURLWithPath: "/")
        for (i, c) in components.enumerated() {
            if i == 0 { continue } // first is "/"
            accum = accum.appendingPathComponent(c)
            out.append((c, accum))
        }
        // Leading "/" segment — shows as "Computer".
        let rootLabel = Host.current().localizedName ?? "Computer"
        out.insert((rootLabel, URL(fileURLWithPath: "/")), at: 0)
        return out
    }
}
