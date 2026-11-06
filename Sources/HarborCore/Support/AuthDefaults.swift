import Foundation

/// Non-secret defaults shared by the native clients.
///
/// Harbor never bundles an OAuth client secret: a native app can't keep one
/// confidential. Sign-in with the built-in client ID uses GitHub's device flow,
/// which needs only the public client ID. People who bring their own OAuth app
/// (e.g. GitHub Enterprise) can still use the browser loopback flow with their
/// own secret; it is stored in their Keychain, never in source.
public enum HarborAuthDefaults {
    /// Public identifier of Harbor's GitHub OAuth app. Device Flow must be
    /// enabled on that app in GitHub's developer settings.
    public static let clientID = "Ov23livmbs19VYbpm3KQ"
    public static let loopbackPort: Int = 53682
    public static let loopbackHost: String = "127.0.0.1"  // Must match the callback URL exactly
    public static let githubHost = URL(string: "https://github.com")!
    public static let apiHost = URL(string: "https://api.github.com")!
}
