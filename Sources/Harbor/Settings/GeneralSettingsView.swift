import AppKit
import HarborCore
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var session: Session
    let appState: AppState

    var body: some View {
        ZStack {
            LiquidGlassBackground()

            ScrollView {
                VStack(spacing: 24) {
                    // Launch at Login Section
                    GlassCard {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "power")
                                    .font(.title2)
                                    .foregroundStyle(.blue)
                                Text("Startup")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                Spacer()
                            }

                            Toggle(isOn: self.$session.settings.launchAtLogin) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Launch at login")
                                        .font(.body)
                                    Text("Automatically opens Harbor when you start your Mac.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(SettingsToggleStyle())
                            .onChange(of: self.session.settings.launchAtLogin) { _, value in
                                LaunchAtLoginHelper.set(enabled: value)
                                self.appState.persistSettings()
                            }
                        }
                    }

                    // Display Section
                    GlassCard {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "paintbrush")
                                    .font(.title2)
                                    .foregroundStyle(.purple)
                                Text("Display")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                Spacer()
                            }

                            VStack(spacing: 16) {
                                Toggle(isOn: self.$session.settings.appearance.showContributionHeader) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Contribution header")
                                            .font(.body)
                                        Text("Show your GitHub activity heatmap in the menu bar.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .toggleStyle(SettingsToggleStyle())
                                .onChange(of: self.session.settings.appearance.showContributionHeader) { _, _ in
                                    self.appState.persistSettings()
                                }

                                Divider()
                                    .opacity(0.5)

                                SettingsPicker(
                                    title: "Activity feed",
                                    icon: "activity",
                                    selection: self.$session.settings.appearance.activityScope,
                                    options: GlobalActivityScope.allCases
                                ) { scope in
                                    Text(scope.label)
                                }
                                .onChange(of: self.session.settings.appearance.activityScope) { _, _ in
                                    self.appState.persistSettings()
                                    self.appState.requestRefresh()
                                }

                                Divider()
                                    .opacity(0.5)

                                SettingsPicker(
                                    title: "Repository heatmap",
                                    icon: "square.grid.3x3",
                                    selection: self.$session.settings.heatmap.display,
                                    options: HeatmapDisplay.allCases
                                ) { display in
                                    Text(display.label)
                                }
                                .onChange(of: self.session.settings.heatmap.display) { _, _ in
                                    self.appState.persistSettings()
                                }

                                Divider()
                                    .opacity(0.5)

                                SettingsPicker(
                                    title: "Heatmap window",
                                    icon: "calendar",
                                    selection: self.$session.settings.heatmap.span,
                                    options: HeatmapSpan.allCases
                                ) { span in
                                    Text(span.label)
                                }
                                .onChange(of: self.session.settings.heatmap.span) { _, _ in
                                    self.appState.persistSettings()
                                    self.appState.updateHeatmapRange(now: Date())
                                }
                            }
                        }
                    }

                    // Repositories Section
                    GlassCard {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "folder")
                                    .font(.title2)
                                    .foregroundStyle(.green)
                                Text("Repositories")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                Spacer()
                            }

                            VStack(spacing: 16) {
                                SettingsPicker(
                                    title: "Repositories shown",
                                    icon: "list.bullet",
                                    selection: self.$session.settings.repoList.displayLimit,
                                    options: [3, 6, 9, 12]
                                ) { Text("\($0)") }

                                Divider()
                                    .opacity(0.5)

                                SettingsPicker(
                                    title: "Menu sort",
                                    icon: "arrow.up.arrow.down",
                                    selection: self.$session.settings.repoList.menuSortKey,
                                    options: RepositorySortKey.settingsCases
                                ) { sortKey in
                                    Text(sortKey.settingsLabel)
                                }
                                .onChange(of: self.session.settings.repoList.menuSortKey) { _, _ in
                                    self.appState.persistSettings()
                                }

                                Divider()
                                    .opacity(0.5)

                                Toggle(isOn: self.$session.settings.repoList.showForks) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Include forked repositories")
                                            .font(.body)
                                        Text("Show repositories you have forked from others.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .toggleStyle(SettingsToggleStyle())
                                .onChange(of: self.session.settings.repoList.showForks) { _, _ in
                                    self.appState.persistSettings()
                                    self.appState.requestRefresh(cancelInFlight: true)
                                }

                                Divider()
                                    .opacity(0.5)

                                Toggle(isOn: self.$session.settings.repoList.showArchived) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Include archived repositories")
                                            .font(.body)
                                        Text("Show repositories that have been archived.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .toggleStyle(SettingsToggleStyle())
                                .onChange(of: self.session.settings.repoList.showArchived) { _, _ in
                                    self.appState.persistSettings()
                                    self.appState.requestRefresh(cancelInFlight: true)
                                }
                            }
                        }
                    }

                    // Refresh Section
                    GlassCard {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                    .font(.title2)
                                    .foregroundStyle(.orange)
                                Text("Refresh")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                Spacer()
                            }

                            VStack(spacing: 16) {
                                SettingsPicker(
                                    title: "Auto-refresh interval",
                                    icon: "clock",
                                    selection: self.$session.settings.refreshInterval,
                                    options: RefreshInterval.allCases
                                ) { interval in
                                    Text(interval.label)
                                }
                                .onChange(of: self.session.settings.refreshInterval) { _, _ in
                                    self.appState.persistSettings()
                                    self.appState.restartRefreshTimer()
                                }

                                Divider()
                                    .opacity(0.5)

                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Manual refresh")
                                            .font(.body)
                                        Text("Click the refresh icon in the menu bar to fetch latest data.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button {
                                        Task { await self.appState.refreshAllData() }
                                    } label: {
                                        HStack {
                                            Image(systemName: "arrow.clockwise")
                                            Text("Refresh Now")
                                        }
                                        .font(.callout)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.orange.opacity(0.1))
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    // Updates Section
                    GlassCard {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "arrow.down.circle")
                                    .font(.title2)
                                    .foregroundStyle(.green)
                                Text("Updates")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                Spacer()
                                if SparkleController.shared.updateStatus.isUpdateReady {
                                    Text("Update Available")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue)
                                        .clipShape(Capsule())
                                }
                            }

                            VStack(spacing: 16) {
                                Toggle(isOn: self.$session.settings.autoCheckForUpdates) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Automatic updates")
                                            .font(.body)
                                        Text("Automatically check for updates daily.")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                    }
                                }
                                .toggleStyle(SettingsToggleStyle())
                                .onChange(of: self.session.settings.autoCheckForUpdates) { _, value in
                                    SparkleController.shared.automaticallyChecksForUpdates = value
                                    self.appState.persistSettings()
                                }

                                Divider()
                                    .opacity(0.5)

                                Toggle(isOn: self.$session.settings.autoDownloadUpdates) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Auto-download updates")
                                            .font(.body)
                                        Text("Download updates in the background.")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                    }
                                }
                                .toggleStyle(SettingsToggleStyle())
                                .onChange(of: self.session.settings.autoDownloadUpdates) { _, value in
                                    SparkleController.shared.automaticallyDownloadsUpdates = value
                                    self.appState.persistSettings()
                                }

                                Divider()
                                    .opacity(0.5)

                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Version")
                                            .font(.body)
                                        Text("Current version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button {
                                        SparkleController.shared.checkForUpdates()
                                    } label: {
                                        HStack {
                                            Image(systemName: "arrow.clockwise")
                                            Text("Check Now")
                                        }
                                        .font(.callout)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.blue.opacity(0.1))
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!SparkleController.shared.canCheckForUpdates)
                                }
                            }
                        }
                    }

                    // Quit Button
                    HStack {
                        Spacer()
                        Button(role: .destructive) {
                            NSApp.terminate(nil)
                        } label: {
                            HStack {
                                Image(systemName: "xmark.circle")
                                Text("Quit Harbor")
                            }
                            .font(.callout)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.red.opacity(0.1))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
                .padding(20)
            }
        }
    }
}

// MARK: - Supporting Views

struct SettingsToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 12) {
            configuration.label

            Spacer()

            RoundedRectangle(cornerRadius: 16)
                .fill(configuration.isOn ? Color.blue : Color.gray.opacity(0.3))
                .frame(width: 44, height: 24)
                .overlay(
                    Circle()
                        .fill(Color.white)
                        .padding(2)
                        .offset(x: configuration.isOn ? 10 : -10)
                )
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isOn)
                .onTapGesture {
                    configuration.isOn.toggle()
                }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            configuration.isOn.toggle()
        }
    }
}

struct SettingsPicker<T: Hashable, Content: View>: View {
    let title: String
    let icon: String
    @Binding var selection: T
    let options: [T]
    @ViewBuilder let label: (T) -> Content

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            Text(title)
                .font(.body)

            Spacer()

            Picker("", selection: self.$selection) {
                ForEach(options, id: \.self) { option in
                    label(option)
                        .tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 150)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            )
        }
    }
}

#Preview {
    GeneralSettingsView(
        session: Session(),
        appState: AppState(platform: ApplePlatformServices())
    )
    .frame(width: 480, height: 600)
}
