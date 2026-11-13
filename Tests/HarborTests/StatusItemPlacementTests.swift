import CoreGraphics
@testable import Harbor
import Testing

/// Geometry from Sriinnu's 14" MacBook Pro on macOS 27: a 1512-wide screen whose notch
/// spans x 663.5–848.5 at the top 32 points.
struct StatusItemPlacementTests {
    private static let notched = ScreenInfo(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        notch: CGRect(x: 663.5, y: 950, width: 185, height: 32)
    )
    private static let external = ScreenInfo(frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440), notch: nil)

    private static func item(x: CGFloat, width: CGFloat = 30) -> CGRect {
        CGRect(x: x, y: 950, width: width, height: 32)
    }

    @Test
    func clearOfTheNotchIsVisible() {
        let placement = StatusItemPlacement.evaluate(itemFrame: Self.item(x: 1100), screens: [Self.notched], windowVisible: true)
        #expect(placement == .visible)
    }

    @Test
    func touchingTheNotchEdgeIsStillVisible() {
        // The menu opened at x 847: only 1.5 points of padding sit under the housing.
        let placement = StatusItemPlacement.evaluate(itemFrame: Self.item(x: 847), screens: [Self.notched], windowVisible: true)
        #expect(placement == .visible)
    }

    @Test
    func mostlyUnderTheNotchIsHidden() {
        let placement = StatusItemPlacement.evaluate(itemFrame: Self.item(x: 830), screens: [Self.notched], windowVisible: true)
        #expect(placement == .underNotch)
    }

    @Test
    func pushedOffEveryScreenIsOffScreen() {
        let placement = StatusItemPlacement.evaluate(itemFrame: Self.item(x: -40), screens: [Self.notched], windowVisible: true)
        #expect(placement == .offScreen)
    }

    @Test
    func occludedWindowIsOffScreen() {
        let placement = StatusItemPlacement.evaluate(itemFrame: Self.item(x: 1100), screens: [Self.notched], windowVisible: false)
        #expect(placement == .offScreen)
    }

    @Test
    func secondDisplayWithoutNotchIsVisible() {
        let placement = StatusItemPlacement.evaluate(
            itemFrame: CGRect(x: 2000, y: 1408, width: 30, height: 32),
            screens: [Self.notched, Self.external],
            windowVisible: true
        )
        #expect(placement == .visible)
    }

    @Test
    func missingOrCollapsedFrameIsUnknown() {
        #expect(StatusItemPlacement.evaluate(itemFrame: nil, screens: [Self.notched], windowVisible: true) == .unknown)
        #expect(StatusItemPlacement.evaluate(itemFrame: Self.item(x: 900, width: 0), screens: [Self.notched], windowVisible: true) == .unknown)
    }

    @Test
    func onlyHiddenPlacementsHaveAMessage() {
        #expect(StatusItemPlacement.visible.message == nil)
        #expect(StatusItemPlacement.unknown.message == nil)
        #expect(StatusItemPlacement.underNotch.message != nil)
        #expect(StatusItemPlacement.offScreen.message != nil)
    }
}
