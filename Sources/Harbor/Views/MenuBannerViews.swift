import HarborCore
import SwiftUI

struct MenuLoggedOutView: View {
    var body: some View {
        VStack(spacing: 12) {
            // Harbor anchor icon with gradient
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.2), .purple.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)

                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .padding(.top, 8)

            VStack(spacing: 6) {
                Text("Sign in to see your repositories")
                    .font(.headline)
                    .fontWeight(.semibold)

                Text("Connect GitHub, Azure DevOps, or GitLab to load your pins and activity.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 20)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .padding(.vertical, 8)
    }
}

struct MenuEmptyStateView: View {
    let title: String
    let subtitle: String

    init(
        title: String = "No repositories yet",
        subtitle: String = "Pin a repository to see activity here."
    ) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.cyan.opacity(0.15), .blue.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)

                Image(systemName: "tray.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 4) {
                Text(self.title)
                    .font(.headline)
                    .fontWeight(.medium)

                Text(self.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 130)
        .padding(.vertical, 8)
    }
}

struct RateLimitBanner: View {
    let reset: Date
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(.orange.opacity(0.15))
                    .frame(width: 24, height: 24)

                Image(systemName: "clock.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }

            Text("Rate limit resets \(RelativeFormatter.string(from: self.reset, relativeTo: Date()))")
                .font(.caption)
                .lineLimit(2)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.orange.opacity(0.05))
        )
        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rate limit reset: \(RelativeFormatter.string(from: self.reset, relativeTo: Date()))")
    }
}

struct ErrorBanner: View {
    let message: String
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(.red.opacity(0.15))
                    .frame(width: 24, height: 24)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }

            Text(self.message)
                .font(.caption)
                .lineLimit(2)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.red.opacity(0.05))
        )
        .foregroundStyle(MenuHighlightStyle.error(self.isHighlighted))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(self.message)")
    }
}

struct MenuInfoTextRowView: View {
    let text: String
    let lineLimit: Int
    private let iconColumnWidth: CGFloat = 18
    private let iconSpacing: CGFloat = 8

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: self.iconSpacing) {
            SubmenuIconPlaceholderView(font: .caption)

            Text(self.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(self.lineLimit)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, MenuStyle.cardHorizontalPadding)
        .padding(.vertical, MenuStyle.cardVerticalPadding)
    }
}
