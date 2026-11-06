import AppKit
import Foundation
import OSLog
import HarborCore

/// Handles GitHub App OAuth using browser + loopback, PKCE, and refresh tokens.
@MainActor
final class OAuthCoordinator {
    private let platform: PlatformServices
    private let tokenRefresher: OAuthTokenRefresher
    private let logger = Logger(subsystem: "com.sriinnu.harbor", category: "oauth")
    private let signposter = OSSignposter(subsystem: "com.sriinnu.harbor", category: "oauth")
    private var lastHost: URL = .init(string: "https://github.com")!
    private var cachedTokens: OAuthTokens?
    private var hasLoadedTokens = false

    init(platform: PlatformServices = ApplePlatformServices()) {
        self.platform = platform
        self.tokenRefresher = OAuthTokenRefresher(tokenStorage: platform.tokenStorage)
    }

    func login(clientID: String, clientSecret: String, host: URL, loopbackPort: Int) async throws {
        let normalizedHost = try OAuthLoginFlow.normalizeHost(host)
        self.lastHost = normalizedHost
        let flow = OAuthLoginFlow(platform: self.platform) { url in
            NSWorkspace.shared.open(url)
        }
        let tokens = try await flow.login(
            clientID: clientID,
            clientSecret: clientSecret,
            host: normalizedHost,
            loopbackPort: loopbackPort
        )
        self.cachedTokens = tokens
        self.hasLoadedTokens = true
        await DiagnosticsLogger.shared.message("Login succeeded; tokens stored via platform services.")
    }

    /// Sign in with GitHub's device flow: no client secret involved.
    /// `onCode` runs once GitHub issues the code the user must enter.
    func loginWithDeviceFlow(
        clientID: String,
        host: URL,
        onCode: @MainActor (DeviceAuthorization) -> Void
    ) async throws {
        let normalizedHost = try OAuthLoginFlow.normalizeHost(host)
        self.lastHost = normalizedHost
        let flow = OAuthDeviceFlow(tokenStorage: self.platform.tokenStorage)
        let authorization = try await flow.start(clientID: clientID, host: normalizedHost)
        onCode(authorization)
        let tokens = try await flow.poll(authorization, clientID: clientID, host: normalizedHost)
        self.cachedTokens = tokens
        self.hasLoadedTokens = true
        await DiagnosticsLogger.shared.message("Device-flow login succeeded; tokens stored via platform services.")
    }

    func logout() async {
        self.platform.tokenStorage.clear()
        self.cachedTokens = nil
        self.hasLoadedTokens = false
        await DiagnosticsLogger.shared.message("Logged out; tokens cleared from platform storage.")
    }

    func loadTokens() -> OAuthTokens? {
        if self.hasLoadedTokens { return self.cachedTokens }
        self.hasLoadedTokens = true
        let tokens = try? self.platform.tokenStorage.load()
        self.cachedTokens = tokens
        return tokens
    }

    func refreshIfNeeded() async throws -> OAuthTokens? {
        let signpost = self.signposter.beginInterval("refreshIfNeeded")
        defer { self.signposter.endInterval("refreshIfNeeded", signpost) }
        if let tokens = self.cachedTokens, tokens.expiresAt.map({ $0 > Date().addingTimeInterval(60) }) != false {
            return tokens
        }
        let refreshed = try await self.tokenRefresher.refreshIfNeeded(host: self.lastHost)
        if refreshed != nil {
            self.cachedTokens = refreshed
            self.hasLoadedTokens = true
        }
        return refreshed
    }

    // MARK: - Installation token

    // Installation flow removed: this app now uses user OAuth only.

    // PEM resolution removed; GitHub App installation tokens are not used.
}
