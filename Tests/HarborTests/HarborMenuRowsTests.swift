import AppKit
@testable import Harbor
import HarborCore
import SwiftUI
import Testing

@MainActor
struct HarborMenuRowsTests {
    private func height(_ view: some View) -> CGFloat {
        let item = MenuItemViewFactory().makeItem(
            for: view, enabled: true, highlightable: true, showsSubmenuIndicator: false, submenu: nil, target: nil, action: nil
        )
        return (item.view as? MenuItemMeasuring)?.measuredHeight(width: 360) ?? -1
    }

    @Test
    func newRowsHaveRealHeights() {
        let header = MenuAccountHeader(login: "sriinnu", providers: [.github], lastRefresh: nil, isRefreshing: false, onRefresh: {})
        #expect(self.height(header) > 20)
        #expect(self.height(MenuSectionHeader(title: "Needs you · 1")) > 10)
        #expect(self.height(NeedsYouRow(kind: .fail, title: "a/b", detail: "CI failing", age: "1h")) >= 40)
        #expect(self.height(ActivityStripRow(cells: [])) > 15)
        #expect(self.height(Text("plain")) > 10)
    }

    @Test
    func weeklyLevelsScaleAgainstTheBusiestWeek() {
        let day: TimeInterval = 86400
        let start = Date(timeIntervalSince1970: 0)
        let cells = (0 ..< 14).map { HeatmapCell(date: start.addingTimeInterval(Double($0) * day), count: $0 < 7 ? 1 : 4) }
        let levels = ActivityStripRow.weeklyLevels(cells, weeks: 2)
        #expect(levels == [1, 4])
        #expect(ActivityStripRow.weeklyLevels([], weeks: 3) == [0, 0, 0])
    }
}
