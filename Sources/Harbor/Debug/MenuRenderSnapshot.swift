#if DEBUG
import AppKit
import HarborCore

/// Dev aid: `HARBOR_MENU_SNAPSHOT=<dir> open build/macos/Harbor.app` opens the real menu once
/// per theme, renders its window to `<dir>/<theme>.png`, then quits. The theme is only changed
/// in memory, so saved settings stay as they were. Debug builds only.
@MainActor
enum MenuRenderSnapshot {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["HARBOR_MENU_SNAPSHOT"].map { URL(fileURLWithPath: $0) }
    }

    static func run(session: Session, statusItem: NSStatusItem, into directory: URL) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for _ in 0 ..< 60 where !session.hasLoadedRepositories {
            try? await Task.sleep(for: .milliseconds(500))
        }
        self.session = session
        self.statusItem = statusItem
        self.outputDirectory = directory
        self.original = session.settings.appearance.theme
        self.step(HarborThemeID.allCases[...])
    }

    private static var session: Session?
    private static var statusItem: NSStatusItem?
    private static var outputDirectory: URL?
    private static var original = HarborThemeID.native
    private static var log = ""

    /// Timers, not tasks: a menu runs a nested event loop, and work queued from a main-queue
    /// task would wait behind the menu it is meant to close.
    private static func after(_ seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        let timer = Timer(timeInterval: seconds, repeats: false) { _ in MainActor.assumeIsolated(work) }
        RunLoop.main.add(timer, forMode: .common)
    }

    private static func step(_ remaining: ArraySlice<HarborThemeID>) {
        guard let id = remaining.first, let session, let statusItem else {
            self.finish()
            return
        }
        session.settings.appearance.theme = id
        ActiveTheme.apply(id)
        self.after(0.4) {
            self.after(1.5) { self.capture(id) }
            statusItem.button?.performClick(nil)
            self.step(remaining.dropFirst())
        }
    }

    private static func capture(_ id: HarborThemeID) {
        guard let menu = self.statusItem?.menu, let directory = self.outputDirectory else { return }
        self.log += "\(id.rawValue): items=\(menu.items.count)\n"
        if let window = menu.items.compactMap(\.view).first?.window, let root = window.contentView?.superview {
            self.log += "windowFrame=\(window.frame) opaque=\(window.isOpaque)\n\(self.tree(root, depth: 0))"
            if let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
                root.cacheDisplay(in: root.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: directory.appendingPathComponent("\(id.rawValue).png"))
            }
        }
        menu.cancelTracking()
    }

    private static func finish() {
        self.session?.settings.appearance.theme = self.original
        if let directory = self.outputDirectory {
            try? self.log.write(to: directory.appendingPathComponent("log.txt"), atomically: true, encoding: .utf8)
        }
        NSApp.terminate(nil)
    }

    private static func tree(_ view: NSView, depth: Int) -> String {
        guard depth < 5 else { return "" }
        let line = String(repeating: "  ", count: depth) + "\(type(of: view)) \(view.frame)\n"
        return line + view.subviews.map { self.tree($0, depth: depth + 1) }.joined()
    }
}
#endif
