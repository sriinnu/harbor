import Foundation
import HarborCore

/// A repository as a boat in the Harbor view, built only from what Harbor actually knows.
struct HarborBoat: Identifiable, Equatable {
    enum Condition: Equatable {
        case moored
        case listing
        case storm

        var label: String {
            switch self {
            case .moored: "moored"
            case .listing: "listing with local drift"
            case .storm: "in a storm, CI failing"
            }
        }
    }

    let id: String
    let name: String
    let condition: Condition
    /// Share of the last 14 days with at least one commit, 0...1; or, in the panel, how
    /// recently the repo saw activity (see `recencyTide`).
    let tide: Double

    /// The panel never loads every repo's contribution days (that would be a request per repo),
    /// so its water height is how recent the latest activity is: full today, empty at 14 days.
    static func recencyTide(of date: Date?, now: Date) -> Double {
        guard let date else { return 0 }
        let days = now.timeIntervalSince(date) / 86400
        return min(max(1 - days / 14, 0), 1)
    }

    init(repo: RepositoryDisplayModel, now: Date = Date(), tideFromRecency: Bool = false) {
        self.id = repo.title
        self.name = repo.source.name
        if repo.ciStatus == .failing {
            self.condition = .storm
        } else if let state = repo.localStatus?.syncState, state != .synced, state != .unknown {
            self.condition = .listing
        } else {
            self.condition = .moored
        }
        if tideFromRecency {
            self.tide = Self.recencyTide(of: repo.source.latestActivity?.date, now: now)
            return
        }
        let cutoff = now.addingTimeInterval(-14 * 86400)
        let activeDays = repo.source.heatmap.filter { $0.date >= cutoff && $0.date <= now && $0.count > 0 }.count
        self.tide = min(Double(activeDays) / 14, 1)
    }
}
