import SwiftUI

// The six token sets, copied from each concept's `--m-*` CSS custom properties.
// Names in the comments are the concept's own.

private extension MenuRowStyle {
    /// The panel's shared geometry: `--m-row-h` 40, `--m-item-px` 8, an 18px glyph box
    /// holding a 16px glyph.
    static func panel(heat: [UInt32], heatRadius: CGFloat = 1.5, tagRadius: CGFloat = 4, heat0Alpha: Double? = nil, glyphEdge: (UInt32, CGFloat)? = nil) -> Self {
        var style = Self()
        style.itemPadding = 8
        style.glyphSize = 16
        style.glyphBox = 18
        style.tagRadius = tagRadius
        style.heatRadius = heatRadius
        if let glyphEdge {
            style.glyphEdge = Color(hex: glyphEdge.0)
            style.glyphEdgeWidth = glyphEdge.1
        }
        style.heat = heat.enumerated().map { index, hex in
            Color(hex: hex, opacity: index == 0 ? (heat0Alpha ?? 1) : 1)
        }
        return style
    }
}

extension HarborPanelSkin {
    static let navy = Self(
        surface: .gradient([Color(hex: 0x112352), Color(hex: 0x0D1B42), Color(hex: 0x0B173A)]),
        border: Edge(color: Color(hex: 0x2A3F73), width: 1),
        separator: Color(hex: 0x9B7001, opacity: 0.62),
        hover: Color(hex: 0x25EBCA, opacity: 0.09),
        selection: Color(hex: 0x25EBCA),
        selectionText: Color(hex: 0x050B1E),
        text: Color(hex: 0xEAF1FB),
        secondaryText: Color(hex: 0xA9B8D3),
        tertiaryText: Color(hex: 0x8A9CBD),
        accent: Color(hex: 0x25EBCA),
        primaryFill: Color(hex: 0x25EBCA),
        primaryText: Color(hex: 0x050B1E),
        segmentFill: Color(hex: 0x081331),
        segmentEdge: Edge(color: Color(hex: 0x22345E), width: 1),
        segmentRadius: 7,
        segmentOnFill: Color(hex: 0x25EBCA),
        segmentOnText: Color(hex: 0x050B1E),
        ok: Notice(
            fill: Color(hex: 0x78D64B, opacity: 0.12), text: Color(hex: 0xA9EC8C),
            edge: Edge(color: Color(hex: 0x78D64B, opacity: 0.35), width: 1)
        ),
        warn: Notice(
            fill: Color(hex: 0xFFC04A, opacity: 0.12), text: Color(hex: 0xFFD68A),
            edge: Edge(color: Color(hex: 0xFFC04A, opacity: 0.4), width: 1)
        ),
        noticeRadius: 6,
        colorScheme: .dark,
        row: .panel(heat: [0xCFE0F5, 0x0F4A57, 0x137F78, 0x1CB79F, 0x25EBCA], heatRadius: 2, heat0Alpha: 0.09)
    )

    static let nativeLight = Self(
        surface: .material(.menu),
        border: Edge(color: Color.white.opacity(0.72), width: 1),
        separator: Color.black.opacity(0.1),
        hover: Color.black.opacity(0.055),
        selection: Color(hex: 0x0064D2),
        selectionText: .white,
        text: Color(hex: 0x1D1D1F),
        secondaryText: Color(hex: 0x303038, opacity: 0.86),
        tertiaryText: Color(hex: 0x303038, opacity: 0.72),
        accent: Color(hex: 0x0058BB),
        primaryFill: Color(hex: 0x0064D2),
        primaryText: .white,
        segmentFill: Color(hex: 0x767680, opacity: 0.14),
        segmentEdge: nil,
        segmentRadius: 999,
        segmentOnFill: .white,
        segmentOnText: Color(hex: 0x1D1D1F),
        ok: Notice(fill: Color(hex: 0x1E8E3E, opacity: 0.13), text: Color(hex: 0x0B5A23), edge: nil),
        warn: Notice(fill: Color(hex: 0xFF9F0A, opacity: 0.2), text: Color(hex: 0x683A00), edge: nil),
        noticeRadius: 8,
        colorScheme: .light,
        cornerRadius: 14,
        itemRadius: 8,
        row: .panel(heat: [0x000000, 0xBBD7FF, 0x74AAF3, 0x2F7BE0, 0x0B4EA6], tagRadius: 5, heat0Alpha: 0.08)
    )

    static let nativeDark = Self(
        surface: .material(.menu),
        border: Edge(color: Color.white.opacity(0.16), width: 1),
        separator: Color.white.opacity(0.12),
        hover: Color.white.opacity(0.08),
        selection: Color(hex: 0x1A66D9),
        selectionText: .white,
        text: Color(hex: 0xF5F5F7),
        secondaryText: Color(hex: 0xEBEBF5, opacity: 0.76),
        tertiaryText: Color(hex: 0xEBEBF5, opacity: 0.62),
        accent: Color(hex: 0x7DBDFF),
        primaryFill: Color(hex: 0x1A66D9),
        primaryText: .white,
        segmentFill: Color(hex: 0x767680, opacity: 0.3),
        segmentEdge: nil,
        segmentRadius: 999,
        segmentOnFill: Color.white.opacity(0.24),
        segmentOnText: .white,
        ok: Notice(fill: Color(hex: 0x30D158, opacity: 0.16), text: Color(hex: 0x86E5A6), edge: nil),
        warn: Notice(fill: Color(hex: 0xFF9F0A, opacity: 0.2), text: Color(hex: 0xFFC874), edge: nil),
        noticeRadius: 8,
        colorScheme: .dark,
        cornerRadius: 14,
        itemRadius: 8,
        row: .panel(heat: [0xFFFFFF, 0x173F7A, 0x2462BC, 0x4A92F2, 0x9CCBFF], tagRadius: 5, heat0Alpha: 0.1)
    )

    static let daylight = Self(
        surface: .solid(.white),
        border: Edge(color: Color(hex: 0x141414), width: 2),
        separator: Color(hex: 0x141414),
        separatorWidth: 2,
        separatorInset: 8,
        hover: Color(hex: 0xFFF0B3),
        selection: Color(hex: 0x2148C8),
        selectionText: .white,
        selectionRing: Ring(outer: Edge(color: Color(hex: 0x141414), width: 2)),
        text: Color(hex: 0x141414),
        secondaryText: Color(hex: 0x474641),
        tertiaryText: Color(hex: 0x5C5B55),
        accent: Color(hex: 0x1C3FAE),
        primaryFill: Color(hex: 0x2148C8),
        primaryText: .white,
        segmentFill: .white,
        segmentEdge: Edge(color: Color(hex: 0x141414), width: 2),
        segmentRadius: 8,
        segmentOnFill: Color(hex: 0xFFD23F),
        segmentOnText: Color(hex: 0x141414),
        segmentOnRing: Color(hex: 0x141414),
        ok: Notice(
            fill: Color(hex: 0xDDF3E2), text: Color(hex: 0x0E4A20), edge: Edge(color: Color(hex: 0x141414), width: 2)
        ),
        warn: Notice(
            fill: Color(hex: 0xFFE38A), text: Color(hex: 0x4A3000), edge: Edge(color: Color(hex: 0x141414), width: 2)
        ),
        noticeRadius: 8,
        colorScheme: .light,
        cornerRadius: 10,
        hasShadow: false,
        row: .panel(heat: [0xECE8DC, 0xC9D6FA, 0x8EA8F0, 0x4F73DE, 0x1F3FAE], heatRadius: 1, glyphEdge: (0x141414, 1.6))
    )

    static let nightWatch = Self(
        surface: .solid(Color(hex: 0x0E1A40)),
        border: Edge(color: Color(hex: 0xDCE7FF), width: 2),
        separator: Color(hex: 0x6F80B4),
        separatorInset: 8,
        hover: Color(hex: 0x18275A),
        selection: Color(hex: 0x8EC5FF),
        selectionText: Color(hex: 0x071232),
        selectionRing: Ring(outer: Edge(color: Color(hex: 0xDCE7FF), width: 2)),
        text: Color(hex: 0xEEF3FF),
        secondaryText: Color(hex: 0xB4C2E6),
        tertiaryText: Color(hex: 0x8C9CC8),
        accent: Color(hex: 0xA9D3FF),
        primaryFill: Color(hex: 0x8EC5FF),
        primaryText: Color(hex: 0x071232),
        segmentFill: Color(hex: 0x0A1433),
        segmentEdge: Edge(color: Color(hex: 0x8FA2D6), width: 1.5),
        segmentRadius: 6,
        segmentOnFill: Color(hex: 0xDCE7FF),
        segmentOnText: Color(hex: 0x071232),
        ok: Notice(
            fill: Color(hex: 0x0F3A2E), text: Color(hex: 0x9BF0C0), edge: Edge(color: Color(hex: 0x4FD18B), width: 2)
        ),
        warn: Notice(
            fill: Color(hex: 0x3E2A08), text: Color(hex: 0xFFD08A), edge: Edge(color: Color(hex: 0xFFB547), width: 2)
        ),
        noticeRadius: 4,
        colorScheme: .dark,
        cornerRadius: 6,
        itemRadius: 4,
        hasShadow: false,
        row: .panel(heat: [0x1A2752, 0x28467F, 0x3D6DB0, 0x66A0E6, 0xA9D3FF], heatRadius: 1, tagRadius: 3, glyphEdge: (0xDCE7FF, 1.3))
    )

    static let chart: Self = {
        var row = MenuRowStyle.panel(heat: [0xE6E8E0, 0xCFE3EC, 0x9CC8E5, 0x4F92C6, 0x1D5C96], heatRadius: 0, tagRadius: 2)
        row.itemPadding = 7
        row.sectionSize = 12
        row.sectionTopPadding = 7
        return Self(
            surface: .solid(Color(hex: 0xFFFEF9)),
            border: Edge(color: Color(hex: 0x18222E), width: 1),
            insetRule: Edge(color: Color(hex: 0x18222E), width: 2),
            separator: Color(hex: 0x18222E, opacity: 0.3),
            separatorInset: 4,
            hover: Color(hex: 0x2E6EA0, opacity: 0.1),
            selection: Color(hex: 0xA3227D),
            selectionText: .white,
            text: Color(hex: 0x18222E),
            secondaryText: Color(hex: 0x4A5866),
            tertiaryText: Color(hex: 0x5E6B78),
            accent: Color(hex: 0x8C1B6A),
            primaryFill: Color(hex: 0xA3227D),
            primaryText: .white,
            segmentFill: .clear,
            segmentEdge: Edge(color: Color(hex: 0x18222E), width: 1),
            segmentRadius: 3,
            segmentOnFill: Color(hex: 0x18222E),
            segmentOnText: Color(hex: 0xFFFEF9),
            ok: Notice(
                fill: Color(hex: 0xE5EFD9), text: Color(hex: 0x234D1E), edge: Edge(color: Color(hex: 0x5E8C4A), width: 1)
            ),
            warn: Notice(
                fill: Color(hex: 0xFBF0C6), text: Color(hex: 0x5E4300), edge: Edge(color: Color(hex: 0xB89A2E), width: 1)
            ),
            noticeRadius: 2,
            colorScheme: .light,
            cornerRadius: 3,
            padding: 8,
            itemRadius: 2,
            row: row
        )
    }()

    static let flagsLight = flags(dark: false)
    static let flagsDark = flags(dark: true)

    /// Signal Flags: solid, heavy ink, taller rows and larger type; light and dark are the
    /// same design with the ink and paper swapped.
    private static func flags(dark: Bool) -> Self {
        let paper: UInt32 = dark ? 0x0B0D12 : 0xFFFFFF
        let ink: UInt32 = dark ? 0xF5F7FA : 0x0B0D12
        let selection: UInt32 = dark ? 0xF2F4F8 : 0x0B0D12
        let selectionText: UInt32 = dark ? 0x0B0D12 : 0xFFFFFF
        var row = MenuRowStyle.panel(
            heat: dark ? [0x0B0D12, 0x22396E, 0x3D63BD, 0x86A6EC, 0xD2DFFF] : [0xFFFFFF, 0xC4D3F5, 0x7D9BDD, 0x3459B5, 0x00247D],
            heatRadius: 1,
            glyphEdge: (ink, 1.4)
        )
        row.itemPadding = 12
        row.rowHeight = 52
        row.headHeight = 48
        row.nameSize = 15
        row.detailSize = 13
        row.tagSize = 12
        row.tagPaddingX = 6
        row.tagWeight = .semibold
        row.sectionSize = 13
        row.sectionTopPadding = 8
        row.sectionBottomPadding = 4
        row.heatEdge = Color(hex: dark ? 0x9AA3B2 : 0x5C6370)
        return Self(
            surface: .solid(Color(hex: paper)),
            border: Edge(color: Color(hex: ink), width: 2),
            separator: Color(hex: dark ? 0x9AA3B2 : 0x5C6370),
            separatorWidth: 2,
            separatorInset: 12,
            hover: Color(hex: dark ? 0x222836 : 0xE3E8F1),
            selection: Color(hex: selection),
            selectionText: Color(hex: selectionText),
            selectionRing: Ring(
                outer: Edge(color: Color(hex: selection), width: 2),
                inner: Edge(color: Color(hex: selectionText), width: 2)
            ),
            text: Color(hex: ink),
            secondaryText: Color(hex: dark ? 0xC9CFDA : 0x3B4250),
            tertiaryText: Color(hex: dark ? 0xB8C0CD : 0x4A5161),
            accent: Color(hex: dark ? 0xA8C1FF : 0x0A3A8C),
            primaryFill: Color(hex: ink),
            primaryText: Color(hex: paper),
            segmentFill: Color(hex: paper),
            segmentEdge: Edge(color: Color(hex: ink), width: 2),
            segmentRadius: 8,
            segmentOnFill: Color(hex: ink),
            segmentOnText: Color(hex: paper),
            ok: Notice(fill: Color(hex: paper), text: Color(hex: ink), edge: Edge(color: Color(hex: ink), width: 2)),
            warn: Notice(
                fill: Color(hex: dark ? 0x2A230A : 0xFFF1B3), text: Color(hex: ink),
                edge: Edge(color: Color(hex: dark ? 0xFFD84D : 0x0B0D12), width: 2)
            ),
            noticeRadius: 6,
            colorScheme: dark ? .dark : .light,
            cornerRadius: 10,
            itemHeight: 32,
            hasShadow: false,
            row: row
        )
    }
}
