import Foundation

/// Non-secret defaults shared by the native clients.
///
/// An OAuth client secret is intentionally never bundled with Harbor. Native
/// applications cannot keep one confidential; users supply credentials for their
/// own OAuth application and they are stored in the system Keychain after login.
public enum HarborAuthDefaults {
    public static let clientID = ""
    public static let clientSecret = ""
    public static let loopbackPort: Int = 53682
    public static let loopbackHost = "127.0.0.1"
    public static let githubHost = URL(string: "https://github.com")!
    public static let apiHost = URL(string: "https://api.github.com")!
}
