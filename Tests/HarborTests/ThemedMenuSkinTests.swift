import AppKit
@testable import Harbor
import HarborCore
import Testing

@MainActor
struct ThemedMenuSkinTests {
    private final class Target: NSObject {
        var fired = false
        @objc func fire(_: NSMenuItem) { self.fired = true }
    }

    private static func sampleMenu(target: Target) -> NSMenu {
        let menu = NSMenu()
        let action = NSMenuItem(title: "Open", action: #selector(Target.fire), keyEquivalent: "")
        action.target = target
        menu.addItem(action)
        menu.addItem(.separator())
        return menu
    }

    @Test
    func themedMenuDrawsPlainItemsAndKeepsTheirActions() {
        let manager = StatusBarMenuManager(appState: AppState())
        let builder = StatusBarMenuBuilder(appState: manager.appState, target: manager)
        let target = Target()
        let menu = Self.sampleMenu(target: target)

        ActiveTheme.apply(.navy)
        ThemedMenuSkin(menuBuilder: builder).restyleItems(in: menu)
        ActiveTheme.apply(.native)

        #expect(menu.items.count == 2)
        #expect(menu.items[0].view != nil)
        #expect(menu.items[0].action == #selector(Target.fire))
        #expect(menu.items[1].isSeparatorItem == false)
        #expect(menu.items[1].view != nil)
    }

    @Test
    func nativeThemeLeavesTheMenuAlone() {
        let manager = StatusBarMenuManager(appState: AppState())
        let builder = StatusBarMenuBuilder(appState: manager.appState, target: manager)
        let target = Target()
        let menu = Self.sampleMenu(target: target)

        ActiveTheme.apply(.native)
        ThemedMenuSkin(menuBuilder: builder).restyleItems(in: menu)

        #expect(menu.items[0].view == nil)
        #expect(menu.items[0].target === target)
        #expect(menu.items[1].isSeparatorItem)
    }
}
