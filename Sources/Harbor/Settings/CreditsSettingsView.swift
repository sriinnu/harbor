import SwiftUI

struct CreditsSettingsView: View {
    var body: some View {
        ZStack {
            LiquidGlassBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                // README Section with glass effect
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("📖 About Harbor")
                            .font(.title2)
                            .bold()

                        Text("Harbor keeps your GitHub work close without pulling you into a browser. Pin the repositories that matter and get a calm, glanceable view of CI, releases, activity, and local Git state—right from your system tray or menu bar.")
                            .foregroundStyle(.secondary)

                        Text("Think of Harbor as your home port: everything important in one place, always in sight, never noisy.")
                            .foregroundStyle(.secondary)
                            .italic()
                    }
                }

                // Features Section with glass effect
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                    Text("✨ Features")
                        .font(.title2)
                        .bold()

                    VStack(alignment: .leading, spacing: 6) {
                        FeatureRow(icon: "doc.text.viewfinder", title: "Live Repository Cards", description: "CI status, activity, releases at a glance")
                        FeatureRow(icon: "line.3.horizontal.decrease.circle", title: "Rich Submenus", description: "PRs, issues, releases, workflow runs")
                        FeatureRow(icon: "chart.bar", title: "Global Activity Feed", description: "Contribution heatmap and per-repo graphs")
                        FeatureRow(icon: "chevron.left.forwardslash.chevron.right", title: "Local Git State", description: "Branch info, status, worktrees")
                        FeatureRow(icon: "star.fill", title: "Smart Organization", description: "Pin/hide repos, filters, sorting")
                        FeatureRow(icon: "terminal", title: "CLI Tool", description: "Bundled harbor CLI for automation")
                    }
                }
                }

                // Tech Stack Section with glass effect
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                    Text("🛠 Technology Stack")
                        .font(.title2)
                        .bold()

                    Group {
                        Text("**macOS**")
                            .font(.headline)
                        TechRow(name: "Swift", version: "6.0+")
                        TechRow(name: "SwiftUI", version: "macOS 15.0+")
                        TechRow(name: "Apollo GraphQL", version: "2.0.4")
                        TechRow(name: "Sparkle", version: "2.8.1")
                        TechRow(name: "Kingfisher", version: "8.6.2")
                        TechRow(name: "AppAuth", version: "2.0.0")
                    }

                    Group {
                        Text("**Windows**")
                            .font(.headline)
                            .padding(.top, 8)
                        TechRow(name: "Rust (Tauri)", version: "2.x")
                        TechRow(name: "React + TypeScript", version: "Latest")
                        TechRow(name: "Windows Credential Manager", version: "Native")
                    }
                }
                }

                // Acknowledgments Section with glass effect
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                    Text("🙏 Acknowledgments")
                        .font(.title2)
                        .bold()

                    VStack(alignment: .leading, spacing: 6) {
                        AcknowledgmentRow(project: "SwiftUI", url: "https://developer.apple.com/xcode/swiftui/")
                        AcknowledgmentRow(project: "Tauri", url: "https://tauri.app/")
                        AcknowledgmentRow(project: "Apollo GraphQL", url: "https://www.apollographql.com/")
                        AcknowledgmentRow(project: "Sparkle", url: "https://sparkle-project.org/")
                        AcknowledgmentRow(project: "Kingfisher", url: "https://github.com/onevcat/Kingfisher")
                        AcknowledgmentRow(project: "MenuBarExtraAccess", url: "https://github.com/orchetect/MenuBarExtraAccess")
                    }

                    Text("Inspired by the need for a calm, focused GitHub client that stays out of your way.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .italic()
                        .padding(.top, 8)
                    }
                }

                // Philosophy Section with glass effect
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                    Text("🎯 Philosophy")
                        .font(.title2)
                        .bold()

                    VStack(alignment: .leading, spacing: 8) {
                        PhilosophyRow(icon: "moon.stars", text: "Calm, not noisy")
                        PhilosophyRow(icon: "eye", text: "Glanceable")
                        PhilosophyRow(icon: "hand.raised", text: "Non-intrusive")
                        PhilosophyRow(icon: "scope", text: "Focused: GitHub and Git, done well")
                        PhilosophyRow(icon: "wifi.slash", text: "Offline-friendly")
                        PhilosophyRow(icon: "lock.shield", text: "Privacy-first")
                    }

                    Text("Harbor is for developers who want to stay in flow.")
                        .font(.headline)
                        .foregroundStyle(.blue)
                        .padding(.top, 8)
                    }
                }

                }
                .padding(24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Helper Views

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .bold()
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct TechRow: View {
    let name: String
    let version: String

    var body: some View {
        HStack {
            Text(name)
                .font(.subheadline)
            Spacer()
            Text(version)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AcknowledgmentRow: View {
    let project: String
    let url: String

    var body: some View {
        Button {
            if let url = URL(string: url) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack {
                Image(systemName: "link")
                    .foregroundStyle(.blue)
                Text(project)
                    .font(.subheadline)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}

private struct PhilosophyRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
        }
    }
}
