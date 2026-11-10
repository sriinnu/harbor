import HarborCore
import SwiftUI

/// What the menu shows and how: header, repository list, heatmap.
struct MenuSettingsView: View {
    @Bindable var session: Session
    let appState: AppState

    private static let displayLimits = [3, 6, 9, 12]

    var body: some View {
        SettingsPane {
            Section {
                Picker("Theme", selection: self.$session.settings.appearance.theme) {
                    ForEach(HarborThemeID.allCases, id: \.self) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                .onChange(of: self.session.settings.appearance.theme) { _, _ in
                    self.appState.persistSettings()
                }
            } header: {
                Text("Look")
            } footer: {
                SettingsFooter("Applies to the menu, its heatmaps and this window. Themes other than Liquid Glass replace the heatmap colors below.")
            }

            Section {
                Toggle(isOn: self.$session.settings.appearance.showContributionHeader) {
                    SettingsLabel(title: "Contribution header", detail: "Your GitHub contribution heatmap at the top of the menu.")
                }
                .onChange(of: self.session.settings.appearance.showContributionHeader) { _, _ in
                    self.appState.persistSettings()
                }

                Toggle(isOn: self.$session.settings.appearance.showHarborView) {
                    SettingsLabel(title: "Harbor view", detail: "Your repositories as boats: moored when clean, listing with local drift, a storm for failing CI, the tide for two weeks of commits.")
                }
                .onChange(of: self.session.settings.appearance.showHarborView) { _, _ in
                    self.appState.persistSettings()
                }

                Picker("Activity feed", selection: self.$session.settings.appearance.activityScope) {
                    ForEach(GlobalActivityScope.allCases, id: \.self) { scope in
                        Text(scope.label).tag(scope)
                    }
                }
                .onChange(of: self.session.settings.appearance.activityScope) { _, _ in
                    self.appState.persistSettings()
                    self.appState.requestRefresh()
                }
            } header: {
                Text("Header")
            }

            Section {
                Picker("Repositories shown", selection: self.$session.settings.repoList.displayLimit) {
                    ForEach(Self.displayLimits, id: \.self) { limit in
                        Text("\(limit)").tag(limit)
                    }
                }
                .onChange(of: self.session.settings.repoList.displayLimit) { _, _ in
                    self.appState.persistSettings()
                }

                Picker("Sort by", selection: self.$session.settings.repoList.menuSortKey) {
                    ForEach(RepositorySortKey.settingsCases, id: \.self) { sortKey in
                        Text(sortKey.settingsLabel).tag(sortKey)
                    }
                }
                .onChange(of: self.session.settings.repoList.menuSortKey) { _, _ in
                    self.appState.persistSettings()
                }

                Toggle("Include forks", isOn: self.$session.settings.repoList.showForks)
                    .onChange(of: self.session.settings.repoList.showForks) { _, _ in
                        self.appState.persistSettings()
                        self.appState.requestRefresh(cancelInFlight: true)
                    }

                Toggle("Include archived repositories", isOn: self.$session.settings.repoList.showArchived)
                    .onChange(of: self.session.settings.repoList.showArchived) { _, _ in
                        self.appState.persistSettings()
                        self.appState.requestRefresh(cancelInFlight: true)
                    }
            } header: {
                Text("Repositories")
            } footer: {
                SettingsFooter("Pinned repositories always come first. Pin and hide them in Repositories.")
            }

            Section {
                Picker("Show heatmap", selection: self.$session.settings.heatmap.display) {
                    ForEach(HeatmapDisplay.allCases, id: \.self) { display in
                        Text(self.heatmapDisplayLabel(display)).tag(display)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: self.session.settings.heatmap.display) { _, _ in
                    self.appState.persistSettings()
                }

                Picker("Time span", selection: self.$session.settings.heatmap.span) {
                    ForEach(HeatmapSpan.allCases, id: \.self) { span in
                        Text(span.label).tag(span)
                    }
                }
                .onChange(of: self.session.settings.heatmap.span) { _, _ in
                    self.appState.persistSettings()
                    self.appState.updateHeatmapRange(now: Date())
                }

                Picker("Colors", selection: self.$session.settings.appearance.accentTone) {
                    ForEach(AccentTone.allCases, id: \.self) { tone in
                        Text(tone.label).tag(tone)
                    }
                }
                .onChange(of: self.session.settings.appearance.accentTone) { _, _ in
                    self.appState.persistSettings()
                }
            } header: {
                Text("Repository heatmap")
            } footer: {
                SettingsFooter("GitHub greens keep the classic contribution palette; System accent follows your Mac's accent color.")
            }
        }
    }

    private func heatmapDisplayLabel(_ display: HeatmapDisplay) -> String {
        switch display {
        case .inline: "Inline"
        case .submenu: "In submenu"
        }
    }
}
