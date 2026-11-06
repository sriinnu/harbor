import AppKit
import HarborCore
import SwiftUI

@MainActor
struct AboutSettingsView: View {
    @State private var iconHover = false
    @AppStorage("autoUpdateEnabled") private var autoUpdateEnabled: Bool = true
    @State private var didSyncUpdater = false

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Harbor"
    }

    private var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        let build = Bundle.main.object(forInfoDictionaryKey: "HarborBuildLabel") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    private var buildTimestamp: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "HarborBuildTimestamp") as? String else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        guard let date = parser.date(from: raw) else { return raw }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = .current
        return formatter.string(from: date)
    }

    private var gitCommit: String? {
        Bundle.main.object(forInfoDictionaryKey: "HarborGitCommit") as? String
    }

    var body: some View {
        ZStack {
            LiquidGlassBackground()

            ScrollView {
                VStack(spacing: 8) {
            if let image = NSApplication.shared.applicationIconImage {
                Button {
                    if let url = URL(string: "https://github.com/sriinnu/Harbor") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: 88, height: 88)
                        .cornerRadius(16)
                        .scaleEffect(self.iconHover ? 1.06 : 1.0)
                        .shadow(color: self.iconHover ? .accentColor.opacity(0.25) : .clear, radius: 6)
                        .padding(.bottom, 4)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        self.iconHover = hovering
                    }
                }
            }

            VStack(spacing: 2) {
                Text(self.appName)
                    .font(.title).bold()
                Text("Version \(self.versionString)")
                    .font(.title3)
                    .foregroundStyle(.blue)
                if let buildTimestamp {
                    let suffix: String = {
                        if let git = self.gitCommit, !git.isEmpty, git != "unknown" {
                            return " (\(git))"
                        }
                        return ""
                    }()
                    Text("Built \(buildTimestamp)\(suffix)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 8) {
                    Text("Your development work, safely docked in the menu bar")
                        .font(.subheadline)
                        .bold()
                        .multilineTextAlignment(.center)

                    Text("Harbor keeps your GitHub, Azure DevOps, and GitLab work close without pulling you into a browser. Pin repositories that matter and get a calm, glanceable view of CI, releases, work items, activity, and local Git state.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Divider()
                        .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Why Harbor is Different:")
                            .font(.caption)
                            .bold()

                        DifferentiatorRow(icon: "moon.stars", text: "Calm, not noisy - stays out of your way")
                        DifferentiatorRow(icon: "eye", text: "Glanceable - quick status without context switching")
                        DifferentiatorRow(icon: "chevron.left.forwardslash.chevron.right", text: "Local Git integration - branch status, worktrees")
                        DifferentiatorRow(icon: "wifi.slash", text: "Offline-friendly - works without connectivity")
                        DifferentiatorRow(icon: "lock.shield", text: "Privacy-first - tokens stay on your device")
                        DifferentiatorRow(icon: "square.grid.2x2", text: "Cross-platform - macOS, Windows, Web")
                    }
                    .padding(.horizontal, 8)
                }
            }

            VStack(spacing: 6) {
                AboutLinkRow(icon: "chevron.left.slash.chevron.right", title: "GitHub", url: "https://github.com/sriinnu/Harbor")
                AboutLinkRow(icon: "ant", title: "Issue Tracker", url: "https://github.com/sriinnu/Harbor/issues")
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.vertical, 10)

            if SparkleController.shared.canCheckForUpdates {
                Divider()
                    .padding(.vertical, 6)
                VStack(spacing: 10) {
                    Toggle("Check for updates automatically", isOn: self.$autoUpdateEnabled)
                        .toggleStyle(.checkbox)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Button("Check for Updates…") {
                        SparkleController.shared.checkForUpdates()
                    }
                }
            } else {
                Text("Updates unavailable in this build.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }

            Text("© 2026 Srinivas Pendela. MIT License.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
                .padding(.horizontal, 24)
                .padding(.bottom, 22)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !self.didSyncUpdater else { return }
            if SparkleController.shared.canCheckForUpdates {
                SparkleController.shared.automaticallyChecksForUpdates = self.autoUpdateEnabled
                SparkleController.shared.automaticallyDownloadsUpdates = self.autoUpdateEnabled
            }
            self.didSyncUpdater = true
        }
        .onChange(of: self.autoUpdateEnabled) { _, newValue in
            if SparkleController.shared.canCheckForUpdates {
                SparkleController.shared.automaticallyChecksForUpdates = newValue
                SparkleController.shared.automaticallyDownloadsUpdates = newValue
            }
        }
    }
}

// MARK: - Helper Views

private struct DifferentiatorRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 16)
                .font(.caption)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
