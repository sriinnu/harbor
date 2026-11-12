import SwiftUI

/// The line that shows what was typed to filter the panel's list, and how many rows match.
/// Typing needs no field: the panel takes the keys itself (see `PanelNavigator.type`).
struct PanelFilterBar: View {
    let query: String
    let matches: Int
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(self.skin.secondaryText)
            Text(verbatim: self.query)
                .font(.system(size: self.skin.row.nameSize, weight: .medium))
                .foregroundStyle(self.skin.text)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 4)
            Text("\(self.matches) found · esc clears")
                .font(.system(size: self.skin.row.detailSize))
                .foregroundStyle(self.skin.tertiaryText)
        }
        .padding(.horizontal, self.skin.row.itemPadding)
        .padding(.vertical, 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Filter")
        .accessibilityValue("\(self.query), \(self.matches) \(self.matches == 1 ? "match" : "matches")")
        .accessibilityHint("Type to change it. Press Escape to clear.")
    }
}
