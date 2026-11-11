import AppKit
import HarborCore
import SwiftUI

/// The skin the menu draws with. Menu rows are hosted views built on demand,
/// so they read this rather than each observing the settings.
@MainActor
enum ActiveTheme {
    private(set) static var theme = HarborTheme.named(.native)

    static var palette: HarborThemePalette? {
        self.theme.palette(isDark: NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
    }

    /// What a menu should render as. AppKit reuses menu windows, so a window left over
    /// from a light theme has to be told when the next one is dark.
    static var menuAppearance: NSAppearance? {
        switch self.theme.forcedAppearance {
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        case nil: NSApplication.shared.effectiveAppearance
        }
    }

    static func apply(_ id: HarborThemeID) {
        guard id != self.theme.id else { return }
        self.theme = HarborTheme.named(id)
        switch self.theme.forcedAppearance {
        case .light: NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .dark: NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        case nil: NSApplication.shared.appearance = nil
        }
    }
}

extension HarborThemeColor {
    var nsColor: NSColor {
        NSColor(srgbRed: self.red, green: self.green, blue: self.blue, alpha: 1)
    }

    var color: Color { Color(nsColor: self.nsColor) }
}
