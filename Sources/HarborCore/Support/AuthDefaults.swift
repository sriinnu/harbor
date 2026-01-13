import Foundation

public enum HarborAuthDefaults {
    // Harbor GitHub OAuth App
    // Created by: Srinivas Pendela
    // IMPORTANT: This callback URL must match exactly what's in GitHub OAuth App settings
    // Using 127.0.0.1 (not localhost) for better compatibility
    public static let clientID = "Ov23livmbs19VYbpm3KQ"
    public static let clientSecret = "15164cd30ad7e647ab7068482c78ce800d83a96e"
    public static let loopbackPort: Int = 53682
    public static let loopbackHost: String = "127.0.0.1"  // Must match callback URL exactly
    public static let githubHost = URL(string: "https://github.com")!
    public static let apiHost = URL(string: "https://api.github.com")!
}
