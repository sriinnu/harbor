import AppKit
import HarborCore
import SwiftUI

/// Who Harbor is, which version is running, where to get help, and who it stands on.
/// Credits used to be their own tab; they live here now (board item H-063).
@MainActor
struct AboutSettingsView: View {
    private struct Credit: Identifiable {
        var id: String { self.name }
        let name: String
        let role: String
        let url: String
    }

    private static let credits = [
        Credit(name: "Sparkle", role: "Software updates", url: "https://sparkle-project.org"),
        Credit(name: "Kingfisher", role: "Avatar loading", url: "https://github.com/onevcat/Kingfisher"),
        Credit(name: "AppAuth", role: "OAuth sign-in", url: "https://github.com/openid/AppAuth-iOS"),
        Credit(name: "Swift Algorithms", role: "Collection algorithms", url: "https://github.com/apple/swift-algorithms"),
        Credit(name: "Commander", role: "harborcli argument parsing", url: "https://github.com/steipete/Commander")
    ]

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Harbor"
    }

    private var buildDetail: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "HarborBuildTimestamp") as? String else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        var text = raw
        if let date = parser.date(from: raw) {
            text = date.formatted(date: .abbreviated, time: .shortened)
        }
        if let git = Bundle.main.object(forInfoDictionaryKey: "HarborGitCommit") as? String,
           !git.isEmpty, git != "unknown" {
            text += " · \(git)"
        }
        return "Built \(text)"
    }

    var body: some View {
        SettingsPane {
            Section {
                self.header
            }

            Section {
                LabeledContent("Version") {
                    Text(verbatim: Bundle.main.harborVersionDescription)
                        .textSelection(.enabled)
                }
                if SparkleController.shared.canCheckForUpdates {
                    SettingsActionRow {
                        Button("Check for Updates…") {
                            SparkleController.shared.checkForUpdates()
                        }
                    }
                }
            } header: {
                Text("Updates")
            } footer: {
                if !SparkleController.shared.canCheckForUpdates {
                    SettingsFooter("Updates aren't available in this build.")
                }
            }

            Section("Help") {
                LabeledContent("Source code") {
                    SettingsLink(title: "github.com/sriinnu/Harbor", url: "https://github.com/sriinnu/Harbor")
                }
                LabeledContent("Report a problem") {
                    SettingsLink(title: "Open an issue", url: "https://github.com/sriinnu/Harbor/issues")
                }
            }

            Section {
                ForEach(Self.credits) { credit in
                    LabeledContent {
                        SettingsLink(title: "Website", url: credit.url)
                            .accessibilityLabel("\(credit.name) website")
                    } label: {
                        Text(verbatim: credit.name)
                        Text(verbatim: credit.role)
                    }
                }
            } header: {
                Text("Acknowledgements")
            } footer: {
                SettingsFooter("© 2026 Srinivas Pendela. Released under the MIT License.")
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 80, height: 80)
                .accessibilityHidden(true)
            Text(verbatim: self.appName)
                .font(.title.weight(.semibold))
            Text("Your repos, moored in the menu bar.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let buildDetail {
                Text(verbatim: buildDetail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}
