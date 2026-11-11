import AppKit
import SwiftUI

private struct MenuItemHighlightedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var menuItemHighlighted: Bool {
        get { self[MenuItemHighlightedKey.self] }
        set { self[MenuItemHighlightedKey.self] = newValue }
    }
}

@MainActor
enum MenuHighlightStyle {
    static var selectionText: Color {
        ActiveTheme.palette?.selectionText.color ?? Color(nsColor: .selectedMenuItemTextColor)
    }

    static var normalPrimaryText: Color {
        ActiveTheme.palette?.text.color ?? Color(nsColor: .controlTextColor)
    }

    static var normalSecondaryText: Color {
        ActiveTheme.palette?.secondaryText.color ?? Color(nsColor: .secondaryLabelColor)
    }

    static func primary(_ highlighted: Bool) -> Color {
        highlighted ? self.selectionText : self.normalPrimaryText
    }

    static func secondary(_ highlighted: Bool) -> Color {
        guard highlighted else { return self.normalSecondaryText }
        return ActiveTheme.palette?.selectionSecondaryText.color
            ?? Color(nsColor: .selectedMenuItemTextColor).opacity(0.86)
    }

    static func error(_ highlighted: Bool) -> Color {
        highlighted ? self.selectionText : ActiveTheme.palette?.error.color ?? Color(nsColor: .systemRed)
    }

    static func warning(_ highlighted: Bool) -> Color {
        highlighted ? self.selectionText : ActiveTheme.palette?.warning.color ?? Color(nsColor: .systemOrange)
    }

    static func selectionBackground(_ highlighted: Bool) -> Color {
        guard highlighted else { return .clear }
        return ActiveTheme.palette?.selection.color ?? Color(nsColor: .selectedContentBackgroundColor)
    }
}

enum MenuFocusRingStyle {
    static let type: NSFocusRingType = .none
}
