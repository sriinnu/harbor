import Foundation
@testable import HarborCore
import Testing

struct TrafficStatsTests {
    private func day(_ month: Int, _ day: Int, hour: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: 2024, month: month, day: day, hour: hour))!
    }

    @Test
    func dailySeriesFillsMissingDaysWithZeroOldestFirst() {
        let series = TrafficStats.dailySeries(
            [(self.day(3, 15), 4), (self.day(3, 14), 2), (self.day(3, 2), 7)], endingOn: self.day(3, 15, hour: 9)
        )
        // 14 days: Mar 2 ... Mar 15.
        #expect(series == [7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 4])
    }

    @Test
    func dailySeriesDropsDaysOutsideTheWindowAndAddsSameDayPoints() {
        let series = TrafficStats.dailySeries(
            [(self.day(2, 20), 99), (self.day(3, 16), 99), (self.day(3, 15), 1), (self.day(3, 15, hour: 5), 2)],
            endingOn: self.day(3, 15)
        )
        #expect(series == Array(repeating: 0, count: 13) + [3])
    }

    @Test
    func aWindowThatStartsOneDayEarlierKeepsItsOldestDayAndDropsNothing() {
        // GitHub answered with Mar 1 ... Mar 14 for a "now" of Mar 15: 14 days, all counted.
        let points = (1 ... 14).map { (date: self.day(3, $0), count: $0) }
        let series = TrafficStats.dailySeries(points, endingOn: self.day(3, 15, hour: 9))
        #expect(series == Array(1 ... 14))
        #expect(series.reduce(0, +) == 105)
    }

    @Test
    func theViewsEndpointDecodesTotalsAndDays() throws {
        let json = """
        {"count": 14, "uniques": 3, "views": [
          {"timestamp": "2024-03-14T00:00:00Z", "count": 10, "uniques": 2},
          {"timestamp": "2024-03-15T00:00:00Z", "count": 4, "uniques": 1}]}
        """
        let response = try GitHubDecoding.decode(TrafficResponse.self, from: Data(json.utf8))
        #expect(response.count == 14)
        #expect(response.uniques == 3)
        #expect(response.points.map(\.count) == [10, 4])
        #expect(response.points.map(\.date) == [self.day(3, 14), self.day(3, 15)])
    }

    @Test
    func theClonesEndpointDecodesItsOwnKey() throws {
        let json = #"{"count": 2, "uniques": 1, "clones": [{"timestamp": "2024-03-15T00:00:00Z", "count": 2, "uniques": 1}]}"#
        let response = try GitHubDecoding.decode(TrafficResponse.self, from: Data(json.utf8))
        #expect(response.points.map(\.count) == [2])
    }

    @Test
    func statsCachedBeforeTheNewFieldsStillDecode() throws {
        let old = Data(#"{"uniqueVisitors": 5, "uniqueCloners": 2}"#.utf8)
        let stats = try JSONDecoder().decode(TrafficStats.self, from: old)
        #expect(stats == TrafficStats(uniqueVisitors: 5, uniqueCloners: 2))
        #expect(stats.views == nil)
        #expect(!stats.isEmpty)
    }

    @Test
    func emptyMeansEveryCountIsZero() {
        #expect(TrafficStats(uniqueVisitors: 0, uniqueCloners: 0, views: 0, clones: 0).isEmpty)
        #expect(TrafficStats(uniqueVisitors: 0, uniqueCloners: 0).isEmpty)
        #expect(!TrafficStats(uniqueVisitors: 0, uniqueCloners: 0, views: 1, clones: 0).isEmpty)
    }
}
