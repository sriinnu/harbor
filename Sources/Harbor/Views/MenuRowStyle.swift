import SwiftUI

/// Sizes and ramps the shared menu rows draw with. The system menu uses `.menu`; the
/// themed panel sets its own from the concept's CSS tokens (`--m-row-h`, `--m-item-px`,
/// the 18px glyph box, the heat ramp and so on).
struct MenuRowStyle: Equatable {
    var itemPadding: CGFloat = MenuStyle.headerHorizontalPadding
    var rowHeight: CGFloat = 40
    var headHeight: CGFloat = 40
    var glyphSize: CGFloat = 14
    var glyphBox: CGFloat = 14
    /// The comic and high-contrast designs outline every status glyph (`--s-edge`).
    var glyphEdge: Color?
    var glyphEdgeWidth: CGFloat = 1.4
    var nameSize: CGFloat = 13
    var detailSize: CGFloat = 11
    var tagSize: CGFloat = 10
    var tagPaddingX: CGFloat = 5
    var tagWeight: Font.Weight = .medium
    var tagRadius: CGFloat = 4
    var sectionSize: CGFloat = 11
    var sectionTopPadding: CGFloat = 6
    var sectionBottomPadding: CGFloat = 2
    /// nil keeps the activity strip on the theme's accent.
    var heat: [Color]?
    var heatRadius: CGFloat = 1.5
    var heatEdge: Color?

    static let menu = Self()
}

private struct MenuRowStyleKey: EnvironmentKey {
    static let defaultValue = MenuRowStyle.menu
}

extension EnvironmentValues {
    var menuRowStyle: MenuRowStyle {
        get { self[MenuRowStyleKey.self] }
        set { self[MenuRowStyleKey.self] = newValue }
    }
}
