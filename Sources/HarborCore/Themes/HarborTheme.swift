import Foundation

public enum HarborThemeID: String, CaseIterable, Equatable, Codable, Sendable {
    case native
    case navy
    case daylight
    case nightWatch
    case chart
    case flags

    public var label: String {
        switch self {
        case .native: "Liquid Glass Native"
        case .navy: "Harbor Brand Navy"
        case .daylight: "Ligne Claire Daylight"
        case .nightWatch: "Ligne Claire Night Watch"
        case .chart: "Admiralty Chart"
        case .flags: "Signal Flags High Contrast"
        }
    }
}

public struct HarborThemeColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(hex: UInt32) {
        self.red = Double((hex >> 16) & 0xFF) / 255
        self.green = Double((hex >> 8) & 0xFF) / 255
        self.blue = Double(hex & 0xFF) / 255
    }

    /// WCAG 2 contrast ratio against `other`.
    public func contrastRatio(with other: HarborThemeColor) -> Double {
        let values = [self.luminance, other.luminance]
        return (values.max()! + 0.05) / (values.min()! + 0.05)
    }

    private var luminance: Double {
        func linear(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(self.red) + 0.7152 * linear(self.green) + 0.0722 * linear(self.blue)
    }
}

public struct HarborThemePalette: Equatable, Sendable {
    public let text: HarborThemeColor
    public let secondaryText: HarborThemeColor
    public let tertiaryText: HarborThemeColor
    public let background: HarborThemeColor
    public let selection: HarborThemeColor
    public let selectionText: HarborThemeColor
    public let selectionSecondaryText: HarborThemeColor
    public let accent: HarborThemeColor
    public let warning: HarborThemeColor
    public let error: HarborThemeColor
    public let separator: HarborThemeColor
    public let border: HarborThemeColor
}

public enum HarborThemeAppearance: Equatable, Sendable {
    case light
    case dark
}

/// A skin over the shared menu layout. The values come from the six theme designs.
/// `native` has no palettes and uses the system's colors throughout.
public struct HarborTheme: Equatable, Sendable {
    public let id: HarborThemeID
    /// Set when the design only exists in one appearance; `nil` follows the system.
    public let forcedAppearance: HarborThemeAppearance?
    public let selectionRadius: Double
    public let menuBorderWidth: Double
    /// The chart's second, inset ruled line around the menu.
    public let hasInsetRule: Bool
    /// Added above and below each menu row; the high-contrast design has taller rows.
    public let extraRowPadding: Double
    /// Status shown as signal flags, so it never depends on color alone.
    public let usesSignalFlags: Bool
    private let lightPalette: HarborThemePalette?
    private let darkPalette: HarborThemePalette?

    public func palette(isDark: Bool) -> HarborThemePalette? {
        isDark ? (self.darkPalette ?? self.lightPalette) : (self.lightPalette ?? self.darkPalette)
    }

    public static func named(_ id: HarborThemeID) -> HarborTheme {
        switch id {
        case .native: HarborTheme(id: id, forced: nil, radius: 6, border: 0, light: nil, dark: nil)
        case .navy: HarborTheme(id: id, forced: .dark, radius: 6, border: 1, light: nil, dark: .navy)
        case .daylight: HarborTheme(id: id, forced: .light, radius: 6, border: 2, light: .daylight, dark: nil)
        case .nightWatch: HarborTheme(id: id, forced: .dark, radius: 4, border: 2, light: nil, dark: .nightWatch)
        case .chart: HarborTheme(id: id, forced: .light, radius: 2, border: 1, insetRule: true, light: .chart, dark: nil)
        case .flags:
            HarborTheme(id: id, forced: nil, radius: 6, border: 2, rowPadding: 4, flags: true, light: .flagsLight, dark: .flagsDark)
        }
    }

    private init(
        id: HarborThemeID,
        forced: HarborThemeAppearance?,
        radius: Double,
        border: Double,
        insetRule: Bool = false,
        rowPadding: Double = 0,
        flags: Bool = false,
        light: HarborThemePalette?,
        dark: HarborThemePalette?
    ) {
        self.id = id
        self.forcedAppearance = forced
        self.selectionRadius = radius
        self.menuBorderWidth = border
        self.hasInsetRule = insetRule
        self.extraRowPadding = rowPadding
        self.usesSignalFlags = flags
        self.lightPalette = light
        self.darkPalette = dark
    }
}

public extension HarborThemePalette {
    private init(_ hex: [UInt32]) {
        let colors = hex.map(HarborThemeColor.init(hex:))
        self.init(
            text: colors[0], secondaryText: colors[1], tertiaryText: colors[2], background: colors[3],
            selection: colors[4], selectionText: colors[5], selectionSecondaryText: colors[6],
            accent: colors[7], warning: colors[8], error: colors[9],
            separator: colors[10], border: colors[11]
        )
    }

    static let navy = Self([
        0xEAF1FB, 0xA9B8D3, 0x8A9CBD, 0x0D1B42, 0x25EBCA, 0x050B1E, 0x050B1E, 0x25EBCA, 0xFFD68A, 0xFF8A80, 0x9B7001, 0x2A3F73
    ])
    static let daylight = Self([
        0x141414, 0x474641, 0x5C5B55, 0xFFFFFF, 0x2148C8, 0xFFFFFF, 0xE8EDFF, 0x1C3FAE, 0x4A3000, 0xB3261E, 0x141414, 0x141414
    ])
    static let nightWatch = Self([
        0xEEF3FF, 0xB4C2E6, 0x8C9CC8, 0x0E1A40, 0x8EC5FF, 0x071232, 0x0F2350, 0xA9D3FF, 0xFFD08A, 0xFF9A9A, 0x6F80B4, 0xDCE7FF
    ])
    static let chart = Self([
        0x18222E, 0x4A5866, 0x5E6B78, 0xFFFEF9, 0xA3227D, 0xFFFFFF, 0xFFFFFF, 0x8C1B6A, 0x5E4300, 0xB3261E, 0x18222E, 0x18222E
    ])
    static let flagsLight = Self([
        0x0B0D12, 0x3B4250, 0x4A5161, 0xFFFFFF, 0x0B0D12, 0xFFFFFF, 0xE3E7EF, 0x0A3A8C, 0x5E4300, 0xC8102E, 0x5C6370, 0x0B0D12
    ])
    static let flagsDark = Self([
        0xF5F7FA, 0xC9CFDA, 0xB8C0CD, 0x0B0D12, 0xF2F4F8, 0x0B0D12, 0x2A303C, 0xA8C1FF, 0xFFD84D, 0xFF8A65, 0x9AA3B2, 0xF5F7FA
    ])
}
