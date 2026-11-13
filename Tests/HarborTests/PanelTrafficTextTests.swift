@testable import Harbor
import Testing

@MainActor
struct PanelTrafficTextTests {
    @Test
    func valueShowsTotalAndUniqueOrJustUniqueForOldCachedStats() {
        #expect(PanelTrafficSection.value(total: 128, unique: 41) == "128 · 41 unique")
        #expect(PanelTrafficSection.value(total: 1_204, unique: 1_000) == "1,204 · 1,000 unique")
        #expect(PanelTrafficSection.value(total: nil, unique: 41) == "41 unique")
    }

    @Test
    func theEmptyAndUnavailableWording() {
        #expect(PanelTrafficSection.emptyText == "No visitors yet. GitHub keeps the last 14 days.")
        #expect(PanelTrafficSection.unavailableText.hasPrefix("Traffic isn't available."))
    }
}
