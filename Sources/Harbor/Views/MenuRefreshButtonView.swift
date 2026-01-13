import AppKit
import HarborCore
import SwiftUI

struct MenuRefreshButtonView: View {
    let isRefreshing: Bool
    let refreshInterval: RefreshInterval
    let lastRefresh: Date?
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Refresh icon with animation
            Image(systemName: isRefreshing ? "arrow.clockwise" : "arrow.clockwise")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isRefreshing ? .orange : .secondary)
                .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                .animation(
                    isRefreshing
                        ? .linear(duration: 1).repeatForever(autoreverses: false)
                        : .default,
                    value: isRefreshing
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(isRefreshing ? "Refreshing..." : "Refresh")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(isRefreshing ? .orange : .primary)

                Text(lastRefreshText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Auto-refresh indicator
            if refreshInterval != .disabled {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption2)
                    Text(refreshInterval.shortLabel)
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.orange.opacity(0.1))
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isRefreshing else { return }
            onRefresh()
        }
    }

    private var lastRefreshText: String {
        guard let lastRefresh else {
            return "Never refreshed"
        }

        let interval = Date().timeIntervalSince(lastRefresh)
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        MenuRefreshButtonView(
            isRefreshing: false,
            refreshInterval: .fiveMinutes,
            lastRefresh: Date().addingTimeInterval(-300),
            onRefresh: {}
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: 360, height: 44)

        MenuRefreshButtonView(
            isRefreshing: true,
            refreshInterval: .oneMinute,
            lastRefresh: Date(),
            onRefresh: {}
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: 360, height: 44)

        MenuRefreshButtonView(
            isRefreshing: false,
            refreshInterval: .disabled,
            lastRefresh: nil,
            onRefresh: {}
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: 360, height: 44)
    }
}
