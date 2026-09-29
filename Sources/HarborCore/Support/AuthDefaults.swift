import Foundation

public enum HarborAuthDefaults {
    // Harbor GitHub OAuth App
    // Created by: Srinivas Pendela
    // IMPORTANT: This callback URL must match exactly what's in GitHub OAuth App settings
    // Using 127.0.0.1 (not localhost) for better compatibility
    public static let clientID = "Ov23livmbs19VYbpm3KQ"
    // Never hardcoded: read from the Keychain (TokenStore "client" item).
    // Empty until a secret has been stored there; OAuth login fails until then.
    // TODO: first-run flow that saves the secret via TokenStore.save(clientCredentials:).
    public static var clientSecret: String {
        (try? TokenStore.shared.loadClientCredentials()?.clientSecret) ?? ""
    }
    public static let loopbackPort: Int = 53682
    public static let loopbackHost: String = "127.0.0.1"  // Must match callback URL exactly
    public static let githubHost = URL(string: "https://github.com")!
    public static let apiHost = URL(string: "https://api.github.com")!
}
