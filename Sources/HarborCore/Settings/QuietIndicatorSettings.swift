import Foundation

// MARK: - Quiet Indicator Settings

/// Settings for quiet/badge-only notifications
public struct QuietIndicatorSettings: Sendable, Equatable, Codable {
    /// Enable quiet mode
    public var enabled: Bool

    /// Only show badge changes (no menu banner notifications)
    public var badgeOnly: Bool

    /// Quiet hours start time
    public var quietHoursStart: Int // Hour in 24h format (e.g., 22 for 10 PM)

    /// Quiet hours end time
    public var quietHoursEnd: Int // Hour in 24h format (e.g., 8 for 8 AM)

    /// Events that should trigger notifications in quiet mode
    public var allowedEvents: Set<QuietEventType>

    /// Minimum importance level to trigger notifications
    public var minimumImportance: NotificationImportance

    public init(
        enabled: Bool = false,
        badgeOnly: Bool = true,
        quietHoursStart: Int = 22,
        quietHoursEnd: Int = 8,
        allowedEvents: Set<QuietEventType> = QuietEventType.defaultSet,
        minimumImportance: NotificationImportance = .important
    ) {
        self.enabled = enabled
        self.badgeOnly = badgeOnly
        self.quietHoursStart = quietHoursStart
        self.quietHoursEnd = quietHoursEnd
        self.allowedEvents = allowedEvents
        self.minimumImportance = minimumImportance
    }

    /// Default quiet settings
    public static let `default` = QuietIndicatorSettings()

    /// Check if current time is within quiet hours
    public func isQuietHours() -> Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        if quietHoursStart <= quietHoursEnd {
            return hour >= quietHoursStart && hour < quietHoursEnd
        } else {
            // Quiet hours span midnight
            return hour >= quietHoursStart || hour < quietHoursEnd
        }
    }
}

// MARK: - Event Types

/// Types of events that can trigger quiet indicators
public enum QuietEventType: String, Codable, Hashable, Sendable, CaseIterable {
    case prApproved
    case prMerged
    case prReviewRequested
    case ciPassed
    case ciFailed
    case ciFixed
    case releasePublished
    case issueAssigned
    case issueClosed
    case mention
    case newPr
    case newIssue
    case stalePrReminder
    case securityAlert

    public var displayName: String {
        switch self {
        case .prApproved: return "PR Approved"
        case .prMerged: return "PR Merged"
        case .prReviewRequested: return "Review Requested"
        case .ciPassed: return "CI Passed"
        case .ciFailed: return "CI Failed"
        case .ciFixed: return "CI Fixed"
        case .releasePublished: return "Release Published"
        case .issueAssigned: return "Issue Assigned"
        case .issueClosed: return "Issue Closed"
        case .mention: return "Mentioned"
        case .newPr: return "New PR"
        case .newIssue: return "New Issue"
        case .stalePrReminder: return "Stale PR Reminder"
        case .securityAlert: return "Security Alert"
        }
    }

    public var defaultEnabled: Bool {
        switch self {
        case .prApproved, .prMerged, .ciFailed, .securityAlert:
            return true
        case .prReviewRequested, .ciFixed, .releasePublished, .mention:
            return true
        case .ciPassed, .issueAssigned, .issueClosed, .newPr, .newIssue, .stalePrReminder:
            return false
        }
    }

    public static var defaultSet: Set<QuietEventType> {
        Set(allCases.filter { $0.defaultEnabled })
    }
}

// MARK: - Notification Importance

/// Importance levels for notifications
public enum NotificationImportance: String, Sendable, Codable, CaseIterable {
    case low
    case normal
    case important
    case critical

    public var priority: Int {
        switch self {
        case .low: return 1
        case .normal: return 2
        case .important: return 3
        case .critical: return 4
        }
    }

    public var displayName: String {
        switch self {
        case .low: return "Low"
        case .normal: return "Normal"
        case .important: return "Important"
        case .critical: return "Critical"
        }
    }
}

// MARK: - Quiet Indicator Event

/// An event that can trigger a quiet indicator
public struct QuietIndicatorEvent: Identifiable, Sendable, Equatable {
    public let id: String
    public let type: QuietEventType
    public let importance: NotificationImportance
    public let title: String
    public let message: String
    public let repository: String
    public let url: URL?
    public let timestamp: Date

    public init(
        id: String = UUID().uuidString,
        type: QuietEventType,
        importance: NotificationImportance,
        title: String,
        message: String,
        repository: String,
        url: URL? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.importance = importance
        self.title = title
        self.message = message
        self.repository = repository
        self.url = url
        self.timestamp = timestamp
    }

    /// Check if this event should trigger a notification
    public func shouldNotify(settings: QuietIndicatorSettings) -> Bool {
        // Check if quiet mode is enabled
        guard !settings.enabled else {
            // Quiet mode is on - only allow if in allowed events
            return settings.allowedEvents.contains(type) &&
                   importance.priority >= settings.minimumImportance.priority &&
                   !settings.isQuietHours()
        }

        // Quiet mode is off - check quiet hours
        if settings.isQuietHours() {
            return settings.allowedEvents.contains(type) &&
                   importance.priority >= settings.minimumImportance.priority
        }

        // Normal operation - only check importance threshold
        return importance.priority >= settings.minimumImportance.priority
    }
}

// MARK: - Quiet Indicator Manager

/// Manager for quiet indicators and badge-only notifications
public actor QuietIndicatorManager {
    private var pendingEvents: [QuietIndicatorEvent] = []
    private let maxPendingEvents = 50

    public init() {}

    /// Add an event to be processed
    public func addEvent(_ event: QuietIndicatorEvent, settings: QuietIndicatorSettings) async -> Bool {
        guard event.shouldNotify(settings: settings) else {
            return false
        }

        // Add to pending events
        if pendingEvents.count >= maxPendingEvents {
            pendingEvents.removeFirst()
        }
        pendingEvents.append(event)

        return true
    }

    /// Get unacknowledged events
    public func getUnacknowledgedEvents(settings: QuietIndicatorSettings) -> [QuietIndicatorEvent] {
        let now = Date()
        let cutoff = now.addingTimeInterval(-24 * 60 * 60) // Last 24 hours

        return pendingEvents.filter { $0.timestamp > cutoff }
    }

    /// Get event count by type
    public func getEventCount(by type: QuietEventType) -> Int {
        pendingEvents.filter { $0.type == type }.count
    }

    /// Get total unread count
    public var unreadCount: Int {
        pendingEvents.count
    }

    /// Clear all pending events
    public func clearAllEvents() {
        pendingEvents.removeAll()
    }

    /// Clear events for a specific repository
    public func clearEvents(for repository: String) {
        pendingEvents.removeAll { $0.repository == repository }
    }

    /// Acknowledge events (remove them from pending)
    public func acknowledgeEvents(ids: [String]) {
        pendingEvents.removeAll { ids.contains($0.id) }
    }
}

// MARK: - Quiet Indicator Display

/// Represents what should be displayed in the quiet indicator badge
public struct QuietIndicatorBadge: Sendable, Equatable {
    /// Total count of important events
    public let count: Int

    /// Types of events (for icon display)
    public let eventTypes: Set<QuietEventType>

    /// Most important event (for detail display)
    public let topEvent: QuietIndicatorEvent?

    public init(count: Int, eventTypes: Set<QuietEventType>, topEvent: QuietIndicatorEvent?) {
        self.count = count
        self.eventTypes = eventTypes
        self.topEvent = topEvent
    }

    /// Empty badge (no events)
    public static let empty = QuietIndicatorBadge(count: 0, eventTypes: [], topEvent: nil)

    /// Whether the badge should be shown
    public var shouldShow: Bool {
        count > 0
    }

    /// Badge color based on most important event
    public var badgeColor: String {
        guard let event = topEvent else { return "gray" }
        switch event.importance {
        case .critical: return "red"
        case .important: return "orange"
        case .normal: return "blue"
        case .low: return "gray"
        }
    }
}
