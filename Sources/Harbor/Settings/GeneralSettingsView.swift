import AppKit
import HarborCore
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var session: Session
    let appState: AppState

    private var updatesAvailable: Bool {
        SparkleController.shared.canCheckForUpdates
    }

    var body: some View {
        SettingsPane {
            Section("Startup") {
                Toggle(isOn: self.$session.settings.launchAtLogin) {
                    SettingsLabel(title: "Launch at login", detail: "Opens Harbor when you log in to your Mac.")
                }
                .onChange(of: self.session.settings.launchAtLogin) { _, value in
                    LaunchAtLoginHelper.set(enabled: value)
                    self.appState.persistSettings()
                }
            }

            Section {
                LabeledContent {
                    HStack(spacing: 8) {
                        Picker("Refresh every", selection: self.$session.settings.refreshInterval) {
                            ForEach(RefreshInterval.allCases, id: \.self) { interval in
                                Text(interval.label).tag(interval)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .onChange(of: self.session.settings.refreshInterval) { _, _ in
                            self.appState.persistSettings()
                            self.appState.restartRefreshTimer()
                        }

                        Button {
                            Task { await self.appState.refreshAllData() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(self.session.isRefreshing)
                        .help("Refresh now")
                        .accessibilityLabel("Refresh now")
                    }
                } label: {
                    SettingsLabel(title: "Refresh every", detail: self.lastRefreshDetail)
                }
            } header: {
                Text("Refresh")
            } footer: {
                SettingsFooter("Applies to GitHub, Azure DevOps and GitLab. Harbor backs off on its own when a provider rate-limits.")
            }

            Section {
                Toggle("Check for updates automatically", isOn: self.$session.settings.autoCheckForUpdates)
                    .onChange(of: self.session.settings.autoCheckForUpdates) { _, value in
                        SparkleController.shared.automaticallyChecksForUpdates = value
                        self.appState.persistSettings()
                    }
                Toggle("Download updates in the background", isOn: self.$session.settings.autoDownloadUpdates)
                    .onChange(of: self.session.settings.autoDownloadUpdates) { _, value in
                        SparkleController.shared.automaticallyDownloadsUpdates = value
                        self.appState.persistSettings()
                    }
            } header: {
                HStack {
                    Text("Updates")
                    if SparkleController.shared.updateStatus.isUpdateReady {
                        Spacer()
                        SettingsStatus(text: "Update ready to install", kind: .ok)
                            .font(.callout)
                    }
                }
            } footer: {
                SettingsFooter(self.updatesAvailable
                    ? "Harbor checks once a day. Check now from About."
                    : "Updates aren't available in this build. Homebrew and development builds update another way.")
            }
            .disabled(!self.updatesAvailable)

            Section {
                Toggle(isOn: self.$session.settings.diagnosticsEnabled) {
                    SettingsLabel(
                        title: "Diagnostic logging",
                        detail: "Records API, refresh and Git events to help track down problems."
                    )
                }
                .onChange(of: self.session.settings.diagnosticsEnabled) { _, enabled in
                    self.appState.persistSettings()
                    Task { await DiagnosticsLogger.shared.setEnabled(enabled) }
                }
                #if DEBUG
                    Toggle(isOn: self.$session.settings.debugPaneEnabled) {
                        SettingsLabel(title: "Debug tab", detail: "Caches, rate limits and Git diagnostics. Development builds only.")
                    }
                    .onChange(of: self.session.settings.debugPaneEnabled) { _, _ in
                        self.appState.persistSettings()
                    }
                #endif
            } header: {
                Text("Troubleshooting")
            }

            Section {} footer: {
                SettingsActionRow {
                    Button("Quit Harbor") { NSApp.terminate(nil) }
                }
            }
        }
    }

    private var lastRefreshDetail: String? {
        if self.session.isRefreshing { return "Refreshing…" }
        guard let date = self.session.lastRefreshDate else { return nil }
        return "Last refreshed \(RelativeFormatter.string(from: date, relativeTo: Date()))"
    }
}

#Preview {
    GeneralSettingsView(
        session: Session(),
        appState: AppState(platform: ApplePlatformServices())
    )
    .frame(width: 560, height: 620)
}
