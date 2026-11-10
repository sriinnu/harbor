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
                    try? await Task.sleep(for: .seconds(1))
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
        configureImagePipeline()
        NSApp.setActivationPolicy(.accessory)
        if let appState = Self.appState {
            self.statusItemController = StatusItemController(appState: appState)
        }
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

    private func configureImagePipeline() {
        let cache = ImageCache(name: "HarborAvatars")
        // Memory cache: 32MB (avatars are small, we can keep more in memory)
        cache.memoryStorage.config.totalCostLimit = 32 * 1024 * 1024
        // Disk cache: 128MB
        cache.diskStorage.config.sizeLimit = 128 * 1024 * 1024
        // Keep avatars for 7 days
        cache.diskStorage.config.expiration = .days(7)
        // Use defense cache for faster loading (15 minutes)
        cache.memoryStorage.config.expiration = .seconds(15 * 60)
        KingfisherManager.shared.cache = cache

        // Configure downloader for better performance
        let downloader = ImageDownloader.default
        downloader.downloadTimeout = 15.0
        KingfisherManager.shared.downloader = downloader
    }
}
