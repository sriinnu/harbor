import SwiftUI

/// Where the panel's footer buttons point when the app has nothing more specific.
enum HarborLinks {
    /// The Harbor repository.
    static let repository = URL(string: "https://github.com/sriinnu/harbor")!
    /// "Support Harbor" goes to the maintainer's GitHub profile; there is no per-project
    /// sponsor page yet.
    static let support = URL(string: "https://github.com/sriinnu")!
}

/// One footer button: its icon, the words shown on hover or keyboard focus, and its shortcut.
struct PanelFooterItem: Identifiable {
    let id: String
    let symbol: String
    let label: String
    let shortcut: String?
    let action: () -> Void
}

/// The footer as one compact row of icon buttons (Settings, GitHub, Support, About, then
/// Quit on the right), with a caption line naming whichever one is hovered or selected.
/// The mouse and the keyboard share one highlight through the navigator, like `PanelRow`.
struct PanelFooterBar: View {
    let actions: HarborPanelActions
    @Environment(\.harborPanelSkin) private var skin
    @Environment(\.panelNavigator) private var navigator

    static let idPrefix = "footer:"

    private var leading: [PanelFooterItem] {
        [
            PanelFooterItem(id: "footer:settings", symbol: "gearshape", label: "Settings", shortcut: "⌘,", action: self.actions.openSettings),
            PanelFooterItem(id: "footer:github", symbol: "chevron.left.forwardslash.chevron.right", label: "Harbor on GitHub", shortcut: nil, action: self.actions.openGitHub),
            PanelFooterItem(id: "footer:support", symbol: "heart", label: "Support Harbor", shortcut: nil, action: self.actions.supportHarbor),
            PanelFooterItem(id: "footer:about", symbol: "info.circle", label: "About Harbor", shortcut: nil, action: self.actions.openAbout)
        ]
    }

    private var quit: PanelFooterItem {
        PanelFooterItem(id: "footer:quit", symbol: "power", label: "Quit Harbor", shortcut: "⌘Q", action: self.actions.quit)
    }

    private static func caption(_ item: PanelFooterItem?) -> String {
        guard let item else { return " " }
        return item.shortcut.map { "\(item.label)  \($0)" } ?? item.label
    }

    var body: some View {
        let focused = (self.leading + [self.quit]).first { $0.id == self.navigator?.selected }
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 2) {
                ForEach(self.leading) { PanelFooterButton(item: $0) }
                Spacer(minLength: 0)
                PanelFooterButton(item: self.quit)
            }
            Text(Self.caption(focused))
                .font(.system(size: self.skin.row.detailSize))
                .foregroundStyle(self.skin.secondaryText)
                .lineLimit(1)
                .padding(.horizontal, self.skin.row.itemPadding)
                .animation(nil, value: focused?.id)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 4)
    }
}

private struct PanelFooterButton: View {
    let item: PanelFooterItem
    @Environment(\.harborPanelSkin) private var skin
    @Environment(\.panelNavigator) private var navigator

    var body: some View {
        let selected = self.navigator?.selected == self.item.id
        Button(action: self.item.action) {
            Image(systemName: self.item.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? self.skin.selectionText : self.tint)
                .frame(width: 32, height: self.skin.itemHeight)
                .background { if selected { PanelSelectionShape() } }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(self.item.shortcut.map { "\(self.item.label) (\($0))" } ?? self.item.label)
        .accessibilityLabel(self.item.label)
        .onHover { inside in
            if inside {
                self.navigator?.selected = self.item.id
            } else if self.navigator?.selected == self.item.id {
                self.navigator?.selected = nil
            }
        }
        .id(self.item.id)
        .preference(key: PanelNavKey.self, value: [PanelNavItem(id: self.item.id, drillsIn: false, perform: self.item.action)])
    }

    private var tint: Color {
        self.item.id == "footer:support" ? self.skin.accent : self.skin.secondaryText
    }
}
