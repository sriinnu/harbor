#if DEBUG
import AppKit
import SwiftUI

/// Dev aid: `HARBOR_SETTINGS_SNAPSHOT=<dir> open build/macos/Harbor.app` renders every
/// Settings tab to `<dir>/<tab>.png` (light and dark), then quits. The window sits
/// off-screen, so nothing appears or takes focus. Debug builds only.
@MainActor
enum SettingsSnapshot {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["HARBOR_SETTINGS_SNAPSHOT"].map { URL(fileURLWithPath: $0) }
    }

    static func run(appState: AppState, into directory: URL) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let tabs: [(SettingsTab, String)] = [
            (.general, "general"), (.repositories, "repositories"), (.accounts, "accounts"),
            (.advanced, "advanced"), (.credits, "credits"), (.about, "about")
        ]
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for (tab, name) in tabs {
                appState.session.settingsSelectedTab = tab
                let host = NSHostingView(rootView: SettingsView(session: appState.session, appState: appState))
                let window = NSWindow(
                    contentRect: NSRect(x: -20000, y: -20000, width: 540, height: 605),
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
                    let suffix = appearance == .darkAqua ? "-dark" : ""
                    try? rep.representation(using: .png, properties: [:])?
                        .write(to: directory.appendingPathComponent("\(name)\(suffix).png"))
                }
                window.orderOut(nil)
            }
        }
        NSApp.terminate(nil)
    }
}
#endif
