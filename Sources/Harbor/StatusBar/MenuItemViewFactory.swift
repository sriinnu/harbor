import AppKit
import SwiftUI

@MainActor
struct MenuItemViewFactory {
    func makeItem(
        for content: some View,
        enabled: Bool,
        highlightable: Bool = false,
        showsSubmenuIndicator: Bool? = nil,
        submenu: NSMenu? = nil,
        target: AnyObject? = nil,
        action: Selector? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem()
        item.isEnabled = enabled

        if highlightable {
            let highlightState = MenuItemHighlightState()
            let indicator = showsSubmenuIndicator ?? (submenu != nil)
            let wrapped = MenuItemContainerView(
                highlightState: highlightState,
                showsSubmenuIndicator: indicator
            ) {
                content
            }
            item.view = MenuItemHostingView(rootView: AnyView(wrapped), highlightState: highlightState)
        } else {
            item.view = MenuItemHostingView(rootView: AnyView(content))
        }

        item.submenu = submenu
        if let target, let action {
            item.target = target
            item.action = action
        }
        return item
    }

    func updateItem(
        _ item: NSMenuItem,
        with content: some View,
        highlightable: Bool,
        showsSubmenuIndicator: Bool? = nil
    ) {
        guard let hostingView = item.view as? MenuItemHostingView else {
            item.view = self.makeItem(
                for: content,
                enabled: item.isEnabled,
                highlightable: highlightable,
                showsSubmenuIndicator: showsSubmenuIndicator
            ).view
            return
        }

        let indicator = showsSubmenuIndicator ?? (item.submenu != nil)
        let anyView = AnyView(content)
        if highlightable {
            hostingView.updateHighlightableRootView(anyView, showsSubmenuIndicator: indicator)
        } else {
            hostingView.updateRootView(anyView)
        }
    }
}
