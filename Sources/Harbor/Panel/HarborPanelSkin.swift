import AppKit
import HarborCore
import SwiftUI

/// The chrome of Harbor's own menu bar panel: the surface the menu bar icon opens when a
/// theme has a panel design. Rows keep their colors from `HarborMenuInk`; this holds what
/// surrounds them, from each concept's `--m-*` tokens. One layout, six token sets.
struct HarborPanelSkin: Equatable {
    /// What the panel is painted on.
    enum Surface: Equatable {
        /// Top-to-bottom stops at 0%, 42% and 100% (Navy).
        case gradient([Color])
        case solid(Color)
        /// A system material, so it follows light and dark and blurs what is behind it.
        case material(NSVisualEffectView.Material)
    }

    /// A control's outline: a border width and its colour.
    struct Edge: Equatable {
        let color: Color
        let width: CGFloat
    }

    /// A banner's fill, text and optional outline.
    struct Notice: Equatable {
        let fill: Color
        let text: Color
        let edge: Edge?
    }

    /// The ring drawn inside a selected row: an outer band, and optionally a second band
    /// inside it (the high-contrast design's double ring).
    struct Ring: Equatable {
        let outer: Edge
        var inner: Edge?
    }

    var surface: Surface
    var border: Edge
    /// The chart's second, inset ruled line.
    var insetRule: Edge?
    var separator: Color
    var separatorWidth: CGFloat = 1
    var separatorInset: CGFloat = 10
    var hover: Color
    var selection: Color
    var selectionText: Color
    var selectionRing: Ring?
    var text: Color
    var secondaryText: Color
    var tertiaryText: Color
    var accent: Color
    var primaryFill: Color
    var primaryText: Color
    var segmentFill: Color
    var segmentEdge: Edge?
    var segmentRadius: CGFloat
    var segmentOnFill: Color
    var segmentOnText: Color
    var segmentOnRing: Color?
    var ok: Notice
    var warn: Notice
    var noticeRadius: CGFloat
    var colorScheme: ColorScheme
    var cornerRadius: CGFloat = 12
    var padding: CGFloat = 6
    var itemRadius: CGFloat = 6
    var itemHeight: CGFloat = 24
    var hasShadow = true
    var width: CGFloat = 380
    var row = MenuRowStyle()

    /// The panel design for a theme in an appearance, or nil while a theme has none and
    /// still uses the system menu. Forced-appearance themes ignore `isDark`.
    static func forTheme(_ id: HarborThemeID, isDark: Bool) -> Self? {
        switch id {
        case .navy: .navy
        case .native: isDark ? .nativeDark : .nativeLight
        case .daylight: .daylight
        case .nightWatch: .nightWatch
        case .chart: .chart
        case .flags: isDark ? .flagsDark : .flagsLight
        }
    }
}

private struct HarborPanelSkinKey: EnvironmentKey {
    static let defaultValue = HarborPanelSkin.navy
}

extension EnvironmentValues {
    var harborPanelSkin: HarborPanelSkin {
        get { self[HarborPanelSkinKey.self] }
        set { self[HarborPanelSkinKey.self] = newValue }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
