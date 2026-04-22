import SwiftUI

/// Centered icon + title + optional subtitle + optional button.
/// Used for: empty folder, search no-match, permission denied. One layout
/// keeps the three states visually consistent — user always knows "this area
/// is intentionally empty, here's why".
struct EmptyStateView: View {
    let icon: String         // SF Symbol name
    let title: String
    let subtitle: String?
    let action: Action?

    @Environment(\.cairnTheme) private var theme

    struct Action {
        let label: String
        let perform: () -> Void
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.6))
            Text(title)
                .font(theme.bodyFont.weight(.medium))
            if let subtitle {
                Text(subtitle)
                    .font(theme.headerFont)
                    .foregroundStyle(.tertiary)
            }
            if let action {
                Button(action.label, action: action.perform)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Factories

    static func emptyFolder() -> EmptyStateView {
        EmptyStateView(
            icon: "folder",
            title: "Empty folder",
            subtitle: "No files here.",
            action: nil
        )
    }

    static func searchNoMatch(query: String) -> EmptyStateView {
        EmptyStateView(
            icon: "magnifyingglass",
            title: "No matches",
            subtitle: "for \"\(query)\"",
            action: nil
        )
    }

    static func permissionDenied(
        message: String = "The system denied access.",
        onRetry: @escaping () -> Void
    ) -> EmptyStateView {
        EmptyStateView(
            icon: "lock",
            title: "Can't read this folder",
            subtitle: message,
            action: Action(label: "Grant Access…", perform: onRetry)
        )
    }
}
