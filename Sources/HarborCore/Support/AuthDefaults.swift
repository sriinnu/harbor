import Foundation

public enum HarborAuthDefaults {
    // Harbor GitHub OAuth App
    // Created by: Srinivas Pendela
    // App name: Harbor
    // Callback URL: http://localhost:53682/callback
    public static let clientID = "Ov23livmbs19VYbpm3KQ"
    public static let clientSecret = "15164cd30ad7e647ab7068482c78ce800d83a96e"
    public static let loopbackPort: Int = 53682
    public static let githubHost = URL(string: "https://github.com")!
    public static let apiHost = URL(string: "https://api.github.com")!
}
