import Foundation

/// Platform-agnostic protocol for persisting user settings
///
/// Implementations:
/// - macOS/iOS: Uses UserDefaults
/// - Windows: Uses JSON file in AppData + Registry for system integration
/// - Web: Uses database (PostgreSQL via Prisma)
/// - Linux: Uses JSON file in ~/.config
@preconcurrency public protocol UserSettingsStorage: Sendable {
    /// Load user settings from storage
    /// - Returns: UserSettings instance (returns defaults if none stored)
    func load() -> UserSettings

    /// Save user settings to storage
    /// - Parameter settings: The settings to persist
    func save(_ settings: UserSettings)
}

// MARK: - Platform Implementations

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
/// macOS/iOS implementation using UserDefaults
public struct UserDefaultsSettingsStorage: UserSettingsStorage {
    private final class DefaultsWrapper: @unchecked Sendable {
        let defaults: UserDefaults
        init(_ defaults: UserDefaults) {
            self.defaults = defaults
        }
    }

    private let defaultsWrapper: DefaultsWrapper
    private let key: String
    private static let currentVersion = 3

    public init(defaults: UserDefaults = .standard, key: String = "com.sriinnu.athena.harbor.settings") {
        self.defaultsWrapper = DefaultsWrapper(defaults)
        self.key = key
    }

    public func load() -> UserSettings {
        guard let data = defaultsWrapper.defaults.data(forKey: key) else {
            return UserSettings()
        }
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(SettingsEnvelope.self, from: data) {
            var settings = envelope.settings
            if envelope.version < Self.currentVersion {
                Self.applyMigrations(to: &settings, fromVersion: envelope.version)
                self.save(settings)
            }
            return settings
        }
        return UserSettings()
    }

    public func save(_ settings: UserSettings) {
        let envelope = SettingsEnvelope(version: Self.currentVersion, settings: settings)
        if let data = try? JSONEncoder().encode(envelope) {
            defaultsWrapper.defaults.set(data, forKey: self.key)
        }
    }

    private static func applyMigrations(to _: inout UserSettings, fromVersion: Int) {
        guard fromVersion < self.currentVersion else { return }
        // Apply incremental migrations here as settings schema evolves
        // Example:
        // if fromVersion < 2 {
        //     settings.someNewField = defaultValue
        // }
    }
}

private struct SettingsEnvelope: Codable {
    let version: Int
    let settings: UserSettings
}
#endif

// MARK: - JSON File-Based Implementation (Cross-platform fallback)

/// JSON file-based implementation for platforms without UserDefaults
public actor JSONFileSettingsStorage: @preconcurrency UserSettingsStorage {
    private let fileURL: URL
    private static let currentVersion = 3

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Convenience initializer using platform-specific config directory
    public init(appName: String = "RepoBar") throws {
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        let configDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(appName, isDirectory: true)
        #elseif os(Linux)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let configDir = home.appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent(appName, isDirectory: true)
        #else
        // Windows would use %APPDATA%\RepoBar
        let home = FileManager.default.homeDirectoryForCurrentUser
        let configDir = home.appendingPathComponent("AppData", isDirectory: true)
            .appendingPathComponent("Roaming", isDirectory: true)
            .appendingPathComponent(appName, isDirectory: true)
        #endif

        // Create directory if needed
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        self.fileURL = configDir.appendingPathComponent("settings.json")
    }

    public func load() -> UserSettings {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return UserSettings()
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            if let envelope = try? decoder.decode(SettingsEnvelope.self, from: data) {
                var settings = envelope.settings
                if envelope.version < Self.currentVersion {
                    Self.applyMigrations(to: &settings, fromVersion: envelope.version)
                    self.save(settings)
                }
                return settings
            }
            return UserSettings()
        } catch {
            print("Failed to load settings: \(error)")
            return UserSettings()
        }
    }

    public func save(_ settings: UserSettings) {
        let envelope = SettingsEnvelope(version: Self.currentVersion, settings: settings)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(envelope)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save settings: \(error)")
        }
    }

    private static func applyMigrations(to _: inout UserSettings, fromVersion: Int) {
        guard fromVersion < self.currentVersion else { return }
        // Apply migrations here
    }
}

// MARK: - In-Memory Implementation (Testing)

/// In-memory implementation for testing
public actor InMemorySettingsStorage: @preconcurrency UserSettingsStorage {
    private var settings: UserSettings

    public init(initialSettings: UserSettings = UserSettings()) {
        self.settings = initialSettings
    }

    public func load() -> UserSettings {
        return settings
    }

    public func save(_ settings: UserSettings) {
        self.settings = settings
    }
}

// MARK: - Usage Example

/*
 Platform-specific instantiation:

 macOS/iOS:
 let storage: UserSettingsStorage = UserDefaultsSettingsStorage()

 Windows/Linux (JSON file):
 let storage: UserSettingsStorage = try JSONFileSettingsStorage(appName: "RepoBar")

 Web (would use database):
 let storage: UserSettingsStorage = DatabaseSettingsStorage(userId: currentUser.id)

 Testing:
 let storage: UserSettingsStorage = InMemorySettingsStorage()

 Then use the protocol:
 let settings = await storage.load()
 var updated = settings
 updated.appearance.accentTone = .systemAccent
 await storage.save(updated)
 */
