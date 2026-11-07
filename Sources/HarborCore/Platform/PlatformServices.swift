import Foundation

/// Unified protocol bundling all platform-specific services
///
/// This protocol provides a single injection point for all platform dependencies,
/// making it easy to configure HarborCore for different platforms.
///
/// Usage:
/// ```swift
/// // On macOS:
/// let services = MacOSPlatformServices()
/// let core = HarborCore(platform: services)
///
/// // On Windows (via Rust FFI):
/// let services = WindowsPlatformServices()
/// let core = HarborCore(platform: services)
///
/// // For testing:
/// let services = MockPlatformServices()
/// let core = HarborCore(platform: services)
/// ```
public protocol PlatformServices: Sendable {
    /// Secure storage for OAuth tokens and credentials
    var tokenStorage: SecureTokenStorage { get }

    /// HTTP server for OAuth callbacks
    var callbackServer: OAuthCallbackServer { get }

    /// Executable locator for finding binaries like git
    var executableLocator: ExecutableLocator { get }

    /// Storage for user settings and preferences
    var settingsStorage: UserSettingsStorage { get }
}

// MARK: - macOS/iOS Implementation

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
/// macOS/iOS platform services implementation
public struct ApplePlatformServices: PlatformServices {
    public let tokenStorage: SecureTokenStorage
    public let callbackServer: OAuthCallbackServer
    public let executableLocator: ExecutableLocator
    public let settingsStorage: UserSettingsStorage

    public init(
        tokenStorage: SecureTokenStorage? = nil,
        callbackServer: OAuthCallbackServer? = nil,
        executableLocator: ExecutableLocator? = nil,
        settingsStorage: UserSettingsStorage? = nil
    ) {
        self.tokenStorage = tokenStorage ?? KeychainTokenStorage()
        #if os(macOS) || os(iOS)
        self.callbackServer = callbackServer ?? NetworkFrameworkCallbackServer()
        #else
        // tvOS/watchOS don't typically need OAuth callback servers
        self.callbackServer = callbackServer ?? MockCallbackServer()
        #endif
        #if os(macOS)
        self.executableLocator = executableLocator ?? MacOSExecutableLocator()
        #else
        // iOS/tvOS/watchOS don't have git executables
        self.executableLocator = executableLocator ?? MockExecutableLocator(path: nil)
        #endif
        self.settingsStorage = settingsStorage ?? UserDefaultsSettingsStorage()
    }
}
#endif

// MARK: - Mock Implementation (Testing)

/// Mock platform services for testing
public struct MockPlatformServices: PlatformServices {
    public let tokenStorage: SecureTokenStorage
    public let callbackServer: OAuthCallbackServer
    public let executableLocator: ExecutableLocator
    public let settingsStorage: UserSettingsStorage

    public init(
        tokenStorage: SecureTokenStorage? = nil,
        callbackServer: OAuthCallbackServer? = nil,
        executableLocator: ExecutableLocator? = nil,
        settingsStorage: UserSettingsStorage? = nil
    ) {
        self.tokenStorage = tokenStorage ?? InMemoryTokenStorage()
        self.callbackServer = callbackServer ?? MockCallbackServer()
        self.executableLocator = executableLocator ?? MockExecutableLocator()
        self.settingsStorage = settingsStorage ?? InMemorySettingsStorage()
    }
}

// MARK: - Usage in HarborCore

/*
 Example: Update OAuthLoginFlow to use platform services

 Old way (macOS-only):
 let flow = OAuthLoginFlow(
     clientID: "...",
     clientSecret: "...",
     openURL: { url in try NSWorkspace.shared.open(url) }
 )

 New way (cross-platform):
 let services: PlatformServices = ApplePlatformServices()
 let flow = OAuthLoginFlow(
     clientID: "...",
     clientSecret: "...",
     callbackServer: services.callbackServer,
     openURL: { url in try NSWorkspace.shared.open(url) }  // Still platform-specific UI
 )

 Then TokenStore becomes:
 services.tokenStorage.save(tokens: oauthTokens)

 And GitExecutable becomes:
 guard let gitURL = services.executableLocator.locate(executable: "git") else {
     throw GitError.executableNotFound
 }
 */

// MARK: - Platform-Specific Implementations (External)

/*
 Windows implementation (in Rust/Tauri side):

 pub struct WindowsPlatformServices {
     token_storage: WindowsCredentialManagerStorage,
     callback_server: WinSockCallbackServer,
     executable_locator: WindowsExecutableLocator,
     settings_storage: WindowsRegistrySettingsStorage,
 }

 impl PlatformServices for WindowsPlatformServices {
     fn token_storage(&self) -> &dyn SecureTokenStorage {
         &self.token_storage
     }
     // ... etc
 }

 Web implementation (in Next.js side):

 class WebPlatformServices implements PlatformServices {
     tokenStorage: DatabaseTokenStorage;
     callbackServer: NextJSCallbackHandler;
     executableLocator: NoOpExecutableLocator;  // No local executables on web
     settingsStorage: DatabaseSettingsStorage;

     constructor(userId: string) {
         this.tokenStorage = new DatabaseTokenStorage(userId);
         this.callbackServer = new NextJSCallbackHandler();
         this.executableLocator = new NoOpExecutableLocator();
         this.settingsStorage = new DatabaseSettingsStorage(userId);
     }
 }
 */
