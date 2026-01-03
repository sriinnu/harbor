import Foundation

/// Platform-agnostic protocol for locating executable binaries
///
/// Implementations:
/// - macOS: Searches Homebrew, Xcode, System paths
/// - Windows: Searches Program Files, System32, PATH
/// - Linux: Searches /usr/bin, /usr/local/bin, PATH
public protocol ExecutableLocator: Sendable {
    /// Locate an executable by name
    /// - Parameter name: The executable name (e.g., "git")
    /// - Returns: URL to the executable, or nil if not found
    func locate(executable name: String) -> URL?

    /// Get version information for an executable
    /// - Parameter url: URL to the executable
    /// - Returns: Tuple of (version string, error message if any)
    func version(at url: URL) -> (version: String?, error: String?)

    /// Check if running in a sandboxed environment
    var isSandboxed: Bool { get }
}

// MARK: - Platform Implementations

#if os(macOS)
import Security

/// macOS implementation with Homebrew, Xcode, and system paths
public struct MacOSExecutableLocator: ExecutableLocator {
    public init() {}

    public func locate(executable name: String) -> URL? {
        let fileManager = FileManager.default
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let pathCandidates = envPath
            .split(separator: ":")
            .map { "\($0)/\(name)" }

        let preferred: [String] = if isSandboxed {
            // Sandboxed apps can only access certain paths
            [
                "/Library/Developer/CommandLineTools/usr/bin/\(name)",
                "/Applications/Xcode.app/Contents/Developer/usr/bin/\(name)",
                "/Applications/Xcode-beta.app/Contents/Developer/usr/bin/\(name)"
            ]
        } else {
            // Non-sandboxed apps prefer Homebrew installations
            [
                "/opt/homebrew/bin/\(name)",  // Apple Silicon Homebrew
                "/usr/local/bin/\(name)",     // Intel Homebrew
                "/Library/Developer/CommandLineTools/usr/bin/\(name)",
                "/Applications/Xcode.app/Contents/Developer/usr/bin/\(name)"
            ]
        }

        let candidates = preferred + pathCandidates + ["/usr/bin/\(name)"]
        guard let resolved = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) else {
            return nil
        }
        return URL(fileURLWithPath: resolved)
    }

    public func version(at url: URL) -> (version: String?, error: String?) {
        let process = Process()
        process.executableURL = url
        process.arguments = ["--version"]
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
        } catch {
            return (nil, error.localizedDescription)
        }
        process.waitUntilExit()
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if process.terminationStatus != 0 {
            let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return (nil, message.isEmpty ? "\(url.lastPathComponent) --version failed" : message)
        }
        return (trimmed.isEmpty ? nil : trimmed, nil)
    }

    public var isSandboxed: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let entitlement = SecTaskCopyValueForEntitlement(task, "com.apple.security.app-sandbox" as CFString, nil)
        return (entitlement as? Bool) == true
    }
}
#endif

// MARK: - Generic POSIX Implementation (Linux, etc.)

#if os(Linux)
/// Linux/POSIX implementation
public struct POSIXExecutableLocator: ExecutableLocator {
    public init() {}

    public func locate(executable name: String) -> URL? {
        let fileManager = FileManager.default
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let pathCandidates = envPath
            .split(separator: ":")
            .map { "\($0)/\(name)" }

        let preferred = [
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "/bin/\(name)"
        ]

        let candidates = preferred + pathCandidates
        guard let resolved = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) else {
            return nil
        }
        return URL(fileURLWithPath: resolved)
    }

    public func version(at url: URL) -> (version: String?, error: String?) {
        let process = Process()
        process.executableURL = url
        process.arguments = ["--version"]
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
        } catch {
            return (nil, error.localizedDescription)
        }
        process.waitUntilExit()
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if process.terminationStatus != 0 {
            let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return (nil, message.isEmpty ? "\(url.lastPathComponent) --version failed" : message)
        }
        return (trimmed.isEmpty ? nil : trimmed, nil)
    }

    public var isSandboxed: Bool {
        // Linux typically doesn't use app sandboxing in the same way
        return false
    }
}
#endif

// MARK: - Mock Implementation (Testing)

/// Mock implementation for testing
public struct MockExecutableLocator: ExecutableLocator {
    private let mockPath: String?
    private let mockVersion: String?
    private let mockError: String?
    private let mockSandboxed: Bool

    public init(
        path: String? = "/usr/bin/git",
        version: String? = "git version 2.42.0",
        error: String? = nil,
        isSandboxed: Bool = false
    ) {
        self.mockPath = path
        self.mockVersion = version
        self.mockError = error
        self.mockSandboxed = isSandboxed
    }

    public func locate(executable name: String) -> URL? {
        guard let path = mockPath else { return nil }
        return URL(fileURLWithPath: path)
    }

    public func version(at url: URL) -> (version: String?, error: String?) {
        return (mockVersion, mockError)
    }

    public var isSandboxed: Bool {
        mockSandboxed
    }
}

// MARK: - Usage Example

/*
 Platform-specific instantiation:

 macOS:
 let locator: ExecutableLocator = MacOSExecutableLocator()

 Windows (Rust implementation):
 let locator: ExecutableLocator = WindowsExecutableLocator()

 Linux:
 let locator: ExecutableLocator = POSIXExecutableLocator()

 Testing:
 let locator: ExecutableLocator = MockExecutableLocator(path: "/usr/bin/git")

 Then use the protocol:
 if let gitURL = locator.locate(executable: "git") {
     let (version, error) = locator.version(at: gitURL)
     print("Git found at \(gitURL.path), version: \(version ?? "unknown")")
 }
 */
