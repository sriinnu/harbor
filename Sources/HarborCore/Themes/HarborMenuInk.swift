import Foundation

/// The menu's second layer of tokens from the six theme designs: section headings,
/// release tags, the account avatar and the status glyph colors. `nil` from
/// `HarborTheme.ink(isDark:)` means "use the system's colors" (Liquid Glass, dark).
public struct HarborMenuInk: Equatable, Sendable {
    public let section: HarborThemeColor
    public let tagText: HarborThemeColor
    public let tagBorder: HarborThemeColor
    /// nil = no fill behind the tag.
    public let tagFill: HarborThemeColor?
    public let avatarFill: HarborThemeColor
    public let avatarText: HarborThemeColor
    /// nil = no ring.
    public let avatarBorder: HarborThemeColor?
    public let pass: HarborThemeColor
    public let fail: HarborThemeColor
    public let pending: HarborThemeColor
    public let none: HarborThemeColor
    public let review: HarborThemeColor
    public let behind: HarborThemeColor

    /// Text, border or ring, and optional fill: hex values for a tag or the avatar.
    struct Plate {
        let text: UInt32
        let edge: UInt32?
        let fill: UInt32?
    }

    init(
        section: UInt32, tag: Plate, avatar: Plate,
        pass: UInt32, fail: UInt32, pending: UInt32, none: UInt32, review: UInt32, behind: UInt32
    ) {
        self.section = HarborThemeColor(hex: section)
        self.tagText = HarborThemeColor(hex: tag.text)
        self.tagBorder = HarborThemeColor(hex: tag.edge ?? tag.text)
        self.tagFill = tag.fill.map(HarborThemeColor.init(hex:))
        self.avatarFill = HarborThemeColor(hex: avatar.fill ?? 0x808080)
        self.avatarText = HarborThemeColor(hex: avatar.text)
        self.avatarBorder = avatar.edge.map(HarborThemeColor.init(hex:))
        self.pass = HarborThemeColor(hex: pass)
        self.fail = HarborThemeColor(hex: fail)
        self.pending = HarborThemeColor(hex: pending)
        self.none = HarborThemeColor(hex: none)
        self.review = HarborThemeColor(hex: review)
        self.behind = HarborThemeColor(hex: behind)
    }

    static let nativeLight = Self(
        section: 0x46464E, tag: Plate(text: 0x2E2E31, edge: 0xDADADC, fill: 0xF0F0F1), avatar: Plate(text: 0xFFFFFF, edge: nil, fill: 0x0064D2),
        pass: 0x1E8E3E, fail: 0xD70015, pending: 0xB85A00, none: 0x6E6E76, review: 0x0064D2, behind: 0x5B3FD6
    )
    static let navy = Self(
        section: 0xD4AE4A, tag: Plate(text: 0xD4AE4A, edge: 0x9B7001, fill: nil), avatar: Plate(text: 0xEAF1FB, edge: 0x9B7001, fill: 0x16295A),
        pass: 0x78D64B, fail: 0xFF4112, pending: 0xFFC04A, none: 0x8A9CBD, review: 0x25EBCA, behind: 0x9AA8FF
    )
    static let daylight = Self(
        section: 0x474641, tag: Plate(text: 0x141414, edge: 0x141414, fill: 0xFFFFFF), avatar: Plate(text: 0x141414, edge: 0x141414, fill: 0xFFD23F),
        pass: 0x2FA35A, fail: 0xE23B2E, pending: 0xFFC21A, none: 0x55544F, review: 0x2148C8, behind: 0x7B4FD6
    )
    static let nightWatch = Self(
        section: 0xB4C2E6, tag: Plate(text: 0xDCE7FF, edge: 0x8FA2D6, fill: nil), avatar: Plate(text: 0xEEF3FF, edge: 0xDCE7FF, fill: 0x2B3F7E),
        pass: 0x4FD18B, fail: 0xFF6B6B, pending: 0xFFB547, none: 0x8C9CC8, review: 0x8EC5FF, behind: 0xB79CFF
    )
    static let chart = Self(
        section: 0x4A5866, tag: Plate(text: 0x18222E, edge: 0x18222E, fill: nil), avatar: Plate(text: 0x18222E, edge: 0x18222E, fill: 0xFFFEF9),
        pass: 0x1F7A3A, fail: 0xC8102E, pending: 0xF2C200, none: 0x5E6B78, review: 0x1F4E9C, behind: 0xF2C200
    )
    static let flagsLight = Self(
        section: 0x3B4250, tag: Plate(text: 0x0B0D12, edge: 0x0B0D12, fill: 0xFFFFFF), avatar: Plate(text: 0x0B0D12, edge: 0x0B0D12, fill: 0xFFC400),
        pass: 0x00247D, fail: 0xC8102E, pending: 0x6B4E00, none: 0x3B4250, review: 0x00247D, behind: 0x00247D
    )
    static let flagsDark = Self(
        section: 0xC9CFDA, tag: Plate(text: 0xF5F7FA, edge: 0xF5F7FA, fill: 0x0B0D12), avatar: Plate(text: 0x0B0D12, edge: 0xF5F7FA, fill: 0xFFC400),
        pass: 0xA8C1FF, fail: 0xFF8A80, pending: 0xFFD84D, none: 0xC9CFDA, review: 0xA8C1FF, behind: 0xA8C1FF
    )
}

/// How a theme sets its menu section headings ("NEEDS YOU · 3").
public struct HarborSectionStyle: Equatable, Sendable {
    public let uppercase: Bool
    /// Letter spacing in points.
    public let tracking: Double
    public let bold: Bool

    public static let plain = Self(uppercase: false, tracking: 0, bold: false)
}

public extension HarborTheme {
    func ink(isDark: Bool) -> HarborMenuInk? {
        switch self.id {
        case .native: isDark ? nil : .nativeLight
        case .navy: .navy
        case .daylight: .daylight
        case .nightWatch: .nightWatch
        case .chart: .chart
        case .flags: isDark ? .flagsDark : .flagsLight
        }
    }

    var sectionStyle: HarborSectionStyle {
        switch self.id {
        case .navy: HarborSectionStyle(uppercase: true, tracking: 1.05, bold: true)
        case .chart: HarborSectionStyle(uppercase: false, tracking: 1.4, bold: false)
        case .flags: HarborSectionStyle(uppercase: false, tracking: 0, bold: true)
        case .native, .daylight, .nightWatch: .plain
        }
    }
}
