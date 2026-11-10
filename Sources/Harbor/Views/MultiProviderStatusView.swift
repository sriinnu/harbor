import AppKit
import HarborCore
import SwiftUI

/// Shows connection status for all providers and activity notifications
struct MultiProviderStatusView: View {
    @Bindable var session: Session
    let appState: AppState
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Provider connections row
            providerConnectionsRow

            // Activity summary
            activitySummaryRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var providerConnectionsRow: some View {
        HStack(spacing: 8) {
            // GitHub
            if session.isGitHubConnected {
                ProviderBadge(
                    name: "GitHub",
                    icon: "chevron.left.forwardslash.chevron.right",
                    color: .purple,
                    username: session.githubUser?.username
                )
            }

            // Azure DevOps
            if session.isAzureConnected {
                ProviderBadge(
                    name: "Azure",
                    icon: "building.2",
                    color: .blue,
                    username: session.azureUser?.displayName
                )
            }

            // GitLab
            if session.isGitLabConnected {
                ProviderBadge(
                    name: "GitLab",
                    icon: "terminal",
                    color: .orange,
                    username: session.gitlabUser?.name
                )
            }

            Spacer()

            // Connection count
            let connectedCount = connectedProviderCount
            if connectedCount > 1 {
                Text("\(connectedCount) connected")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var activitySummaryRow: some View {
        HStack(spacing: 12) {
            // Pull Requests activity
            if hasRecentActivity {
                ActivityIndicator(
                    icon: "git-pull-request",
                    count: recentPRCount,
                    label: "PRs",
                    color: .purple
                )
            }

            // Issues activity
            if hasRecentActivity {
                ActivityIndicator(
                    icon: "envelope",
                    count: recentIssueCount,
                    label: "Issues",
                    color: .blue
                )
            }

            // Commits activity
            if hasRecentActivity {
                ActivityIndicator(
                    icon: "arrow.triangle.branch",
                    count: recentCommitCount,
                    label: "Commits",
                    color: .green
                )
            }

            Spacer()

            // Refresh status
            if session.hasLoadedRepositories {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                    Text("Updated")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.5)
                    Text("Loading...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var connectedProviderCount: Int {
        var count = 0
        if session.isGitHubConnected { count += 1 }
        if session.isAzureConnected { count += 1 }
        if session.isGitLabConnected { count += 1 }
        return count
    }

    private var hasRecentActivity: Bool {
        !session.globalActivityEvents.isEmpty || !session.globalCommitEvents.isEmpty
    }

    private var recentPRCount: Int {
        session.globalActivityEvents.filter { ($0.eventType ?? "").contains("PullRequest") }.count
    }

    private var recentIssueCount: Int {
        session.globalActivityEvents.filter { ($0.eventType ?? "").contains("Issue") }.count
    }

    private var recentCommitCount: Int {
        session.globalCommitEvents.count
    }
}

// MARK: - Supporting Views

struct ProviderBadge: View {
    let name: String
    let icon: String
    let color: Color
    let username: String?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(name)
                .font(.caption2)
                .fontWeight(.medium)
            if let username = username {
                Text("@\(username)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(color.opacity(0.15))
        )
        .overlay(
            Capsule()
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}

struct ActivityIndicator: View {
    let icon: String
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
            if count > 0 {
                Text("\(count)")
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill((ActiveTheme.palette?.background.color ?? Color(NSColor.windowBackgroundColor)).opacity(0.8))
        )
    }
}

// MARK: - Activity Banner

struct ActivityBanner: View {
    let title: String
    let icon: String
    let count: Int
    let color: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(color)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("\(count) new")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(color.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: 20) {
        // Connected state
        MultiProviderStatusView(
            session: {
                let s = Session()
                s.account = .loggedIn(UserIdentity(
                    username: "testuser",
                    host: URL(string: "https://github.com")!
                ))
                s.isAzureConnected = true
                s.azureUser = AzureDevOpsUser(
                    id: "2",
                    displayName: "Test User",
                    uniqueName: "test@test.com"
                )
                s.hasLoadedRepositories = true
                return s
            }(),
            appState: AppState(platform: ApplePlatformServices())
        )
        .padding()
        .background(Color(NSColor.windowBackgroundColor))

        // Disconnected state
        MultiProviderStatusView(
            session: {
                let s = Session()
                s.hasLoadedRepositories = true
                return s
            }(),
            appState: AppState(platform: ApplePlatformServices())
        )
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
    .frame(width: 340)
}
