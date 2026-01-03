import Foundation
@testable import HarborCore
import Testing

struct ReleaseFormatterTests {
    @Test
    func releasedLabelUsesTodayAndYesterday() {
        let now = Date()
        let today = ReleaseFormatter.releasedLabel(for: now, now: now)
        #expect(today == "today")

        let yesterdayDate = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let yesterday = ReleaseFormatter.releasedLabel(for: yesterdayDate, now: now)
        #expect(yesterday == "yesterday")
    }

    @Test
    func menuLineIncludesName() {
        let now = Date()
        let release = Release(name: "v1.2.3", tag: "v1.2.3", publishedAt: now, url: URL(string: "https://example.com")!)
        let line = ReleaseFormatter.menuLine(for: release, now: now)
        #expect(line.hasPrefix("v1.2.3 • "))
    }
}
