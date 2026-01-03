import SwiftUI

struct RecentListSubmenuRowView: View {
    let title: String
    let systemImage: String
    let badgeText: String?
    let detailText: String?
    let onOpen: (() -> Void)?

    @Environment(\.menuItemHighlighted) private var isHighlighted
    @Environment(\.colorScheme) private var colorScheme

    init(
        title: String,
        systemImage: String,
        badgeText: String? = nil,
        detailText: String? = nil,
        onOpen: (() -> Void)? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.badgeText = badgeText
        self.detailText = detailText
        self.onOpen = onOpen
    }

    var body: some View {
        if let onOpen {
            self.row
                .contentShape(Rectangle())
                .onTapGesture { onOpen() }
        } else {
            self.row
        }
    }

    private var row: some View {
        HStack(alignment: .firstTextBaseline, spacing: MenuStyle.submenuIconSpacing) {
            SubmenuIconColumnView {
                Image(systemName: self.systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .font(.caption)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            }

            Text(self.title)
                .font(.system(size: 14))
                .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
                .lineLimit(1)

            Spacer(minLength: 8)

            if let detailText, detailText.isEmpty == false {
                Text(detailText)
                    .font(.caption2)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(1)
            }

            if let badgeText {
                Text(badgeText)
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(self.badgeForeground)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(self.badgeBackground, in: Capsule(style: .continuous))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(self.badgeBorder, lineWidth: 1)
                    }
                    .padding(.trailing, 16)
                    .accessibilityLabel(Text("Count \(badgeText)"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private var badgeBackground: Color {
        if self.isHighlighted {
            return Color.white.opacity(self.colorScheme == .dark ? 0.22 : 0.18)
        }
        if self.colorScheme == .dark {
            return Color.white.opacity(0.08)
        }
        return Color.black.opacity(0.12)
    }

    private var badgeBorder: Color {
        if self.isHighlighted {
            return Color.white.opacity(self.colorScheme == .dark ? 0.22 : 0.28)
        }
        if self.colorScheme == .dark {
            return Color.white.opacity(0.10)
        }
        return Color.black.opacity(0.18)
    }

    private var badgeForeground: Color {
        self.isHighlighted ? MenuHighlightStyle.selectionText : MenuHighlightStyle.primary(false)
    }
}
