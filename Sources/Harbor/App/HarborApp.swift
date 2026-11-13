import AppKit
import Kingfisher
import HarborCore
import SwiftUI

@main
struct HarborApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    var appDelegate
    @State private var appState: AppState

    init() {
        // Initialize platform services
        let platform = ApplePlatformServices()
        self.appState = AppState(platform: platform)
        AppDelegate.appState = self.appState
        #if DEBUG
            if let directory = SettingsSnapshot.directory {
                let appState = self.appState
                Task { @MainActor in
                    // After the first menu bar icon placement check, so its banner shows.
                    try? await Task.sleep(for: .seconds(3))
                    await SettingsSnapshot.run(appState: appState, into: directory)
                }
            }
        #endif

        // Log platform initialization
        Task { @MainActor in
            await DiagnosticsLogger.shared.message("Platform services initialized: ApplePlatformServices")
            do {
                let hasTokens = try platform.tokenStorage.load() != nil
                await DiagnosticsLogger.shared.message("Token storage status: \(hasTokens ? "tokens present" : "no tokens")")
            } catch {
                await DiagnosticsLogger.shared.message("Token storage check failed: \(error.localizedDescription)")
            }

            #if os(macOS)
            if let gitPath = platform.executableLocator.locate(executable: "git") {
                await DiagnosticsLogger.shared.message("Git executable found at: \(gitPath.path)")
            } else {
                await DiagnosticsLogger.shared.message("Git executable not found")
            }
            #endif
        }
    }

    @SceneBuilder
    var body: some Scene {
        // Comes before Settings: it holds the action that opens that scene.
        Window("Harbor", id: "settings-bridge") {
            SettingsBridgeView(appState: self.appState)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commandsRemoved()

        Settings {
            SettingsView(session: self.appState.session, appState: self.appState)
        }
        .defaultSize(width: SettingsView.size.width, height: SettingsView.size.height)
        .windowResizability(.contentSize)
    }
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by `HarborApp.init`, which runs before the app finishes launching.
    static var appState: AppState?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_: Notification) {
        guard ensureSingleInstance() else {
            NSApp.terminate(nil)
            return
        }
        let removed = LegacyCacheCleanup.runOnce()
        if removed.isEmpty == false {
            Task { await DiagnosticsLogger.shared.message("Removed legacy cache files: " + removed.joined(separator: ", ")) }
        }
        configureImagePipeline()
        NSApp.setActivationPolicy(.accessory)
        if let appState = Self.appState {
            let controller = StatusItemController(appState: appState)
            self.statusItemController = controller
            // The panel's own toggle, so a pinned confirm or a running retire still holds it open.
            GlobalHotkey.shared.onPress = { [weak controller] in
                NSApp.activate(ignoringOtherApps: true)
                controller?.openFromHotkey()
            }
            GlobalHotkey.shared.apply(appState.session.settings.hotkey)
        }
    }

    func applicationWillTerminate(_: Notification) {
        GlobalHotkey.shared.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }
}

extension AppDelegate {
    /// Prevent multiple instances when LS UI flag is unavailable under SwiftPM.
    private func ensureSingleInstance() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return true }
        let others = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleID && !$0.isEqual(NSRunningApplication.current)
        }
        return others.isEmpty
    }

    /// Avatars are downloaded when a row needs one: never read from, never written to disk.
    /// A row that is on screen holds its own image; nothing is kept for the next time.
    private func configureImagePipeline() {
        KingfisherManager.shared.defaultOptions += [.forceRefresh, .cacheMemoryOnly]
        let downloader = ImageDownloader.default
        downloader.downloadTimeout = 15.0
        KingfisherManager.shared.downloader = downloader
    }
}
