import Foundation

// MARK: - Diagnostics Summary

/// Diagnostics summary for Azure DevOps client
public struct AzureDevOpsDiagnosticsSummary: Sendable {
    public let apiHost: URL
    public let organization: String?
    public let defaultProject: String?
    public let rateLimitReset: Date?
    public let lastRateLimitError: String?
    public let backoffEntries: Int
    public let rateLimit: RateLimitSnapshot?

    public static let empty = AzureDevOpsDiagnosticsSummary(
        apiHost: URL(string: "https://dev.azure.com")!,
        organization: nil,
        defaultProject: nil,
        rateLimitReset: nil,
        lastRateLimitError: nil,
        backoffEntries: 0,
        rateLimit: nil
    )
}
