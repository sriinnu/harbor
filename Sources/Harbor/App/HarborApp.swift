import AppKit
import Kingfisher
import MenuBarExtraAccess
import OSLog
import HarborCore
import SwiftUI

@main
struct HarborApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    var appDelegate
    @State private var appState: AppState
    @State private var isMenuPresented = false
    @State private var menuManager: StatusBarMenuManager?
    private let logger = Logger(subsystem: "com.sriinnu.athena.harbor", category: "menu-state")

    init() {
        // Initialize platform services
        let platform = ApplePlatformServices()
        self.appState = AppState(platform: platform)

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
            do {
                if let gitPath = try platform.executableLocator.locate(executable: "git") {
                    await DiagnosticsLogger.shared.message("Git executable found at: \(gitPath.path)")
                } else {
                    await DiagnosticsLogger.shared.message("Git executable not found")
                }
            } catch {
                await DiagnosticsLogger.shared.message("Git executable lookup failed: \(error.localizedDescription)")
            }
            #endif
        }
    }

    @SceneBuilder
    var body: some Scene {
        MenuBarExtra {
            EmptyView()
        } label: {
            StatusItemLabelView(session: self.appState.session)
        }
        .menuBarExtraStyle(.menu)
        .menuBarExtraAccess(isPresented: self.$isMenuPresented) { item in
            self.logMenuEvent("menuBarExtraAccess statusItem=\(self.objectID(item)) menuManager=\(self.menuManager != nil)")
            if self.menuManager == nil {
                self.menuManager = StatusBarMenuManager(appState: self.appState)
            }
            self.menuManager?.attachMainMenu(to: item)
        }
        .onChange(of: self.isMenuPresented) { _, newValue in
            self.logMenuEvent("isMenuPresented=\(newValue)")
        }

        Settings {
            SettingsView(session: self.appState.session, appState: self.appState)
        }
        .defaultSize(width: 540, height: 420)
        .windowResizability(.contentSize)
    }

    private func logMenuEvent(_ message: String) {
        self.logger.info("\(message, privacy: .public)")
        Task { await DiagnosticsLogger.shared.message(message) }
    }

    private func objectID(_ object: AnyObject?) -> String {
        guard let object else { return "nil" }
        return String(ObjectIdentifier(object).hashValue)
    }
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        guard ensureSingleInstance() else {
            NSApp.terminate(nil)
            return
        }
        configureImagePipeline()
        NSApp.setActivationPolicy(.accessory)
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
