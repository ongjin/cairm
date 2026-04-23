import SwiftUI

struct RemoteErrorCard: View {
    let title: String
    let detail: String
    var actions: [Action] = []

    struct Action {
        let label: String
        let handler: () -> Void
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(title).font(.headline)
            }
            Text(detail)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if !actions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(actions.enumerated()), id: \.offset) { _, a in
                        Button(a.label) { a.handler() }
                    }
                }
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.3)))
        .padding(24)
        .frame(maxWidth: 480, alignment: .leading)
    }
}
