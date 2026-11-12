import Foundation

public extension Error {
    /// True for work that was abandoned or superseded (`CancellationError`, `URLError.cancelled`,
    /// or the same code arriving as a plain `NSError`). That is control flow, not a failure.
    var isCancellation: Bool {
        if self is CancellationError { return true }
        if let urlError = self as? URLError { return urlError.code == .cancelled }
        let ns = self as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }

    /// `userFacingMessage` for anything the user should read; nil for a cancellation, so
    /// call sites that show errors can't turn "cancelled" into a banner.
    var reportableMessage: String? {
        self.isCancellation ? nil : self.userFacingMessage
    }

    var userFacingMessage: String {
        if let ghError = self as? GitHubAPIError {
            return ghError.displayMessage
        }
        if let urlError = self as? URLError {
            switch urlError.code {
            case .notConnectedToInternet: return "No internet connection."
            case .timedOut: return "Request timed out."
            case .cannotLoadFromNetwork: return "Rate limited; retry soon."
            case .cannotParseResponse: return "GitHub returned an unexpected response."
            case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
                 .serverCertificateNotYetValid:
                return "Enterprise host certificate is not trusted."
            default: break
            }
        }
        return localizedDescription
    }
}
