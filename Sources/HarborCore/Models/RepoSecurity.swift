import Foundation

public struct DependabotTally: Codable, Equatable, Hashable, Sendable {
    public let critical: Int
    public let high: Int
    public let medium: Int
    public let low: Int

    public init(critical: Int, high: Int, medium: Int, low: Int) {
        self.critical = critical
        self.high = high
        self.medium = medium
        self.low = low
    }

    public var total: Int { self.critical + self.high + self.medium + self.low }

    /// "1 critical, 2 high", most severe first; empty when there are none.
    public var breakdown: String {
        [(self.critical, "critical"), (self.high, "high"), (self.medium, "medium"), (self.low, "low")]
            .filter { $0.0 > 0 }
            .map { "\($0.0) \($0.1)" }
            .joined(separator: ", ")
    }
}

/// Open security alerts as GitHub reports them. `nil` means GitHub didn't tell us
/// (no admin access, or the feature is off for this repository). It is never shown
/// as zero, because "no alerts" and "couldn't look" are different answers.
public struct RepoSecurity: Codable, Equatable, Hashable, Sendable {
    public let dependabot: DependabotTally?
    public let secretLeaks: Int?
    public let codeScanning: Int?

    public init(dependabot: DependabotTally?, secretLeaks: Int?, codeScanning: Int?) {
        self.dependabot = dependabot
        self.secretLeaks = secretLeaks
        self.codeScanning = codeScanning
    }

    public var isAvailable: Bool {
        self.dependabot != nil || self.secretLeaks != nil || self.codeScanning != nil
    }

    public var openAlertCount: Int {
        (self.dependabot?.total ?? 0) + (self.secretLeaks ?? 0) + (self.codeScanning ?? 0)
    }
}

/// Shared wording for the menu and the CLI.
public enum RepoSecurityText {
    public static func dependabot(_ tally: DependabotTally?) -> String {
        guard let tally else { return "Dependabot: unavailable" }
        guard tally.total > 0 else { return "Dependabot: 0 open" }
        return "Dependabot: \(tally.total) open (\(tally.breakdown))"
    }

    public static func count(_ title: String, _ count: Int?) -> String {
        count.map { "\(title): \($0) open" } ?? "\(title): unavailable"
    }
}
