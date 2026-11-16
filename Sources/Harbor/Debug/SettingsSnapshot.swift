#if DEBUG
import AppKit
import HarborCore
import SwiftUI

/// Dev aid: `HARBOR_SETTINGS_SNAPSHOT=<dir> open build/macos/Harbor.app` renders every
/// Settings tab to `<dir>/<tab>.png` (light) and `<tab>-dark.png`, then quits. Each tab is
/// also rendered on its own in a tall window, `<tab>-full.png` / `<tab>-full-dark.png`, so
/// content below the fold can be reviewed. The window sits off-screen, so nothing appears
/// or takes focus. Debug builds only.
@MainActor
enum SettingsSnapshot {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["HARBOR_SETTINGS_SNAPSHOT"].map { URL(fileURLWithPath: $0) }
    }

    private static let tabs: [(SettingsTab, String)] = [
        (.general, "general"), (.menu, "menu"), (.repositories, "repositories"),
        (.accounts, "accounts"), (.localGit, "local-git"), (.about, "about"), (.debug, "debug")
    ]

    static func run(appState: AppState, into directory: URL) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let size = SettingsView.size
        if let raw = ProcessInfo.processInfo.environment["HARBOR_SNAPSHOT_THEME"], let id = HarborThemeID(rawValue: raw) {
            appState.session.settings.appearance.theme = id
            ActiveTheme.apply(id)
        }
        // A theme that forces light or dark never shows the other, so don't render it.
        let appearances: [NSAppearance.Name] = switch ActiveTheme.theme.forcedAppearance {
        case .light: [.aqua]
        case .dark: [.darkAqua]
        case nil: [.aqua, .darkAqua]
        }
        for appearance in appearances {
            let suffix = appearance == .darkAqua ? "-dark" : ""
            for (tab, name) in self.tabs {
                // The real window, tab strip and all (the Debug tab only shows when enabled).
                if tab != .debug {
                    appState.session.settingsSelectedTab = tab
                    await self.render(
                        SettingsView(session: appState.session, appState: appState),
                        size: size,
                        appearance: appearance,
                        to: directory.appendingPathComponent("\(name)\(suffix).png")
                    )
                }
                // The pane alone, tall enough to show everything.
                await self.render(
                    self.pane(tab, appState: appState).frame(width: size.width, height: 1500),
                    size: CGSize(width: size.width, height: 1500),
                    appearance: appearance,
                    to: directory.appendingPathComponent("\(name)-full\(suffix).png")
                )
            }
        }
        NSApp.terminate(nil)
    }

    @ViewBuilder
    private static func pane(_ tab: SettingsTab, appState: AppState) -> some View {
        let session = appState.session
        switch tab {
        case .general: GeneralSettingsView(session: session, appState: appState)
        case .menu: MenuSettingsView(session: session, appState: appState)
        case .repositories: RepoSettingsView(session: session, appState: appState)
        case .accounts: AccountSettingsView(session: session, appState: appState)
        case .localGit: LocalGitSettingsView(session: session, appState: appState)
        case .about: AboutSettingsView()
        case .debug: DebugSettingsView(session: session, appState: appState)
        }
    }

    private static func render(
        _ view: some View,
        size: CGSize,
        appearance: NSAppearance.Name,
        to url: URL
    ) async {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: -20000, y: -20000, width: size.width, height: size.height),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        window.orderFrontRegardless()
        try? await Task.sleep(for: .milliseconds(700)) // let SwiftUI lay out and load
        host.layoutSubtreeIfNeeded()
        let bounds = host.bounds
        if let rep = host.bitmapImageRepForCachingDisplay(in: bounds) {
            host.cacheDisplay(in: bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
        window.orderOut(nil)
    }
}
#endif
