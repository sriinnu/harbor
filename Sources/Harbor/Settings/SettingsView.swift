import HarborCore
import SwiftUI

struct SettingsView: View {
    @Bindable var session: Session
    let appState: AppState

    static let size = CGSize(width: 560, height: 620)
    @Environment(\.colorScheme) private var colorScheme

    private var themePalette: HarborThemePalette? {
        HarborTheme.named(self.session.settings.appearance.theme).palette(isDark: self.colorScheme == .dark)
    }

    var body: some View {
        TabView(selection: self.$session.settingsSelectedTab) {
            GeneralSettingsView(session: self.session, appState: self.appState)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            MenuSettingsView(session: self.session, appState: self.appState)
                .tabItem { Label("Menu", systemImage: "menubar.rectangle") }
                .tag(SettingsTab.menu)
            RepoSettingsView(session: self.session, appState: self.appState)
                .tabItem { Label("Repositories", systemImage: "books.vertical") }
                .tag(SettingsTab.repositories)
            AccountSettingsView(session: self.session, appState: self.appState)
                .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
                .tag(SettingsTab.accounts)
            LocalGitSettingsView(session: self.session, appState: self.appState)
                .tabItem { Label("Local Git", systemImage: "arrow.triangle.branch") }
                .tag(SettingsTab.localGit)
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
            #if DEBUG
                if self.session.settings.debugPaneEnabled {
                    DebugSettingsView(session: self.session, appState: self.appState)
                        .tabItem { Label("Debug", systemImage: "ant") }
                        .tag(SettingsTab.debug)
                }
            #endif
        }
        .tabViewStyle(.automatic)
        .tint(self.themePalette?.accent.color)
        .environment(\.harborThemeBackground, self.themePalette?.background.color)
        .frame(width: Self.size.width, height: Self.size.height)
        .onChange(of: self.session.settings.debugPaneEnabled) { _, enabled in
            #if DEBUG
                if !enabled, self.session.settingsSelectedTab == .debug {
                    self.session.settingsSelectedTab = .general
                }
            #endif
        }
    }
}
