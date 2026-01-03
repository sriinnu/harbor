import Foundation

public extension Error {
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
