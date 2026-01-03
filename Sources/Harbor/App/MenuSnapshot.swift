import Foundation
import HarborCore

struct MenuSnapshot: Equatable {
    let repositories: [Repository]
    let capturedAt: Date

    func isStale(now: Date, interval: TimeInterval) -> Bool {
        now.timeIntervalSince(self.capturedAt) >= interval
    }
}
