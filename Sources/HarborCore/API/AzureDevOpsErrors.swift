import Foundation

public enum AzureDevOpsAPIError: Error {
    case rateLimited(until: Date?, message: String)
    case serviceUnavailable(retryAfter: Date?, message: String)
    case badStatus(code: Int, message: String?)
    case invalidHost
    case invalidPAT
    case invalidOrganization
    case invalidProject
    case unauthorized
    case forbidden

    public var displayMessage: String {
        switch self {
        case let .rateLimited(_, message): message
        case let .serviceUnavailable(_, message): message
        case let .badStatus(code, message): message ?? "Azure DevOps returned \(code)."
        case .invalidHost: "Azure DevOps host must use HTTPS."
        case .invalidPAT: "Personal Access Token is invalid or missing."
        case .invalidOrganization: "Organization name is required."
        case .invalidProject: "Project name or ID is required."
        case .unauthorized: "Authentication failed. Please check your Personal Access Token."
        case .forbidden: "Access forbidden. Your PAT may lack required permissions."
        }
    }

    public var rateLimitedUntil: Date? {
        if case let .rateLimited(until, _) = self { return until }
        return nil
    }

    public var retryAfter: Date? {
        if case let .serviceUnavailable(date, _) = self { return date }
        return nil
    }
}

extension AzureDevOpsAPIError: LocalizedError {
    public var errorDescription: String? { self.displayMessage }
}

struct AzureDevOpsErrorAccumulator {
    private(set) var messages: [String] = []
    private(set) var rateLimit: Date?

    var message: String? { self.messages.first }

    mutating func absorb(_ error: Error) {
        if let azdo = error as? AzureDevOpsAPIError {
            self.updateLimit(with: azdo.rateLimitedUntil ?? azdo.retryAfter)
            self.appendUnique(azdo.displayMessage)
            return
        }
        self.appendUnique(error.localizedDescription)
    }

    private mutating func appendUnique(_ message: String) {
        guard !self.messages.contains(message) else { return }
        self.messages.append(message)
    }

    private mutating func updateLimit(with candidate: Date?) {
        guard let candidate else { return }
        if let current = rateLimit {
            if candidate > current { self.rateLimit = candidate }
        } else {
            self.rateLimit = candidate
        }
    }
}
