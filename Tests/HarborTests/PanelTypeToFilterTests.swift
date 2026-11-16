import Foundation
@testable import Harbor
import Testing

@MainActor
struct PanelTypeToFilterTests {
    private func navigator(scope: String? = "repo:") -> PanelNavigator {
        let navigator = PanelNavigator()
        navigator.setFilterScope(scope)
        return navigator
    }

    @Test
    func typingBuildsTheFilterAndDeleteRemovesTheLastCharacter() {
        let navigator = self.navigator()
        #expect(navigator.type("h"))
        #expect(navigator.type("a"))
        #expect(navigator.filter == "ha")
        #expect(navigator.handle(keyCode: 51))
        #expect(navigator.filter == "h")
    }

    @Test
    func deleteWithNoFilterIsNotConsumed() {
        #expect(self.navigator().handle(keyCode: 51) == false)
    }

    @Test
    func escapeClearsTheFilterOnceThenFallsThrough() {
        let navigator = self.navigator()
        _ = navigator.type("x")
        #expect(navigator.clearFilter())
        #expect(navigator.filter.isEmpty)
        #expect(navigator.clearFilter() == false)
    }

    @Test
    func nothingIsTakenWhereNothingIsFilterable() {
        let navigator = self.navigator(scope: nil)
        #expect(navigator.type("a") == false)
        #expect(navigator.filter.isEmpty)
    }

    @Test
    func aPinnedPanelKeepsItsKeys() {
        let navigator = self.navigator()
        navigator.pin(PanelPin.towerRetire, true)
        #expect(navigator.type("a") == false)
        navigator.pin(PanelPin.towerRetire, false)
        #expect(navigator.type("a"))
        navigator.pin(PanelPin.towerRetire, true)
        #expect(navigator.handle(keyCode: 51) == false)
        #expect(navigator.filter == "a")
    }

    @Test
    func controlCharactersAndALeadingSpaceAreNotSearches() {
        let navigator = self.navigator()
        #expect(navigator.type("\r") == false)
        #expect(navigator.type("\u{F700}") == false)
        #expect(navigator.type(" ") == false)
        #expect(navigator.type("a"))
        #expect(navigator.type(" "))
        #expect(navigator.filter == "a ")
    }

    @Test
    func changingTheScopeStartsAFreshFilter() {
        let navigator = self.navigator()
        _ = navigator.type("abc")
        navigator.setFilterScope("repo:")
        #expect(navigator.filter == "abc")
        navigator.setFilterScope("list:")
        #expect(navigator.filter.isEmpty)
    }

    @Test
    func returnOpensTheFirstMatchWhenNothingIsHighlighted() {
        let navigator = self.navigator()
        var opened: [String] = []
        navigator.update(["need:1", "repo:a", "repo:b"].map { id in PanelNavItem(id: id, drillsIn: true, perform: { opened.append(id) }) })
        _ = navigator.type("a")
        #expect(navigator.handle(keyCode: 36))
        #expect(opened == ["repo:a"])
    }
}
