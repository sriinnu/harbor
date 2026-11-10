import AppKit
@testable import Harbor
import Testing

struct HarborIconViewTests {
    /// A MenuBarExtra label lays images out at their own size, so the logo must
    /// come back at the requested point size, not the PNG's 1024 pt.
    @Test
    @MainActor
    func logoIsSizedForTheMenuBar() throws {
        let image = try #require(HarborIconView.loadHarborLogo(pointSize: 18))
        #expect(image.size == NSSize(width: 18, height: 18))
    }
}
