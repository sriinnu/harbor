import Foundation
import HarborCore
import Testing

struct HarborThemeTests {
    @Test
    func allSixThemesExist() {
        #expect(HarborThemeID.allCases.map(\.label) == [
            "Liquid Glass Native", "Harbor Brand Navy", "Ligne Claire Daylight",
            "Ligne Claire Night Watch", "Admiralty Chart", "Signal Flags High Contrast"
        ])
    }

    @Test(arguments: HarborThemeID.allCases)
    func paletteTextIsReadable(id: HarborThemeID) {
        let theme = HarborTheme.named(id)
        for palette in [theme.palette(isDark: false), theme.palette(isDark: true)].compactMap(\.self) {
            for text in [palette.text, palette.secondaryText, palette.tertiaryText, palette.accent, palette.warning, palette.error] {
                #expect(text.contrastRatio(with: palette.background) >= 4.5)
            }
            #expect(palette.selectionText.contrastRatio(with: palette.selection) >= 4.5)
            #expect(palette.selectionSecondaryText.contrastRatio(with: palette.selection) >= 4.5)
        }
    }

    @Test
    func nativeUsesSystemColors() {
        #expect(HarborTheme.named(.native).palette(isDark: false) == nil)
        #expect(HarborTheme.named(.native).palette(isDark: true) == nil)
    }

    @Test
    func settingsSavedBeforeThemesStillLoad() throws {
        let json = #"{"showContributionHeader":false,"cardDensity":"compact","accentTone":"system","activityScope":"allActivity"}"#
        let settings = try JSONDecoder().decode(AppearanceSettings.self, from: Data(json.utf8))
        #expect(settings.showContributionHeader == false)
        #expect(settings.accentTone == .system)
        #expect(settings.theme == .native)
    }

    @Test
    func themeChoiceRoundTrips() throws {
        var settings = AppearanceSettings()
        settings.theme = .chart
        let decoded = try JSONDecoder().decode(AppearanceSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.theme == .chart)
    }
}
