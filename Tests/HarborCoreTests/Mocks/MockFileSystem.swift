import Foundation
@testable import HarborCore

/// Mock file system for testing file operations without touching real disk
public actor MockFileSystem {
    // MARK: - File Storage

    private var files: [String: Data] = [:]
    private var directories: Set<String> = []
    private var accessHistory: [(path: String, operation: Operation, timestamp: Date)] = []

    public enum Operation: String {
        case read
        case write
        case delete
        case createDirectory
        case fileExists
        case directoryExists
    }

    public init() {
        // Add some default directories
        directories.insert("/")
        directories.insert("/tmp")
        directories.insert("/usr/bin")
        directories.insert("/opt/homebrew/bin")
    }

    // MARK: - File Operations

    /// Check if a file exists at the given path
    public func fileExists(atPath path: String) -> Bool {
        accessHistory.append((path, .fileExists, Date()))
        return files[path] != nil
    }

    /// Check if a directory exists at the given path
    public func directoryExists(atPath path: String) -> Bool {
        accessHistory.append((path, .directoryExists, Date()))
        return directories.contains(path)
    }

    /// Write data to a file
    public func write(_ data: Data, toPath path: String) throws {
        accessHistory.append((path, .write, Date()))

        // Check if parent directory exists
        let parentPath = (path as NSString).deletingLastPathComponent
        guard directories.contains(parentPath) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)
        }

        files[path] = data
    }

    /// Read data from a file
    public func read(fromPath path: String) throws -> Data {
        accessHistory.append((path, .read, Date()))

        guard let data = files[path] else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
        }

        return data
    }

    /// Delete a file
    public func deleteFile(atPath path: String) throws {
        accessHistory.append((path, .delete, Date()))

        guard files[path] != nil else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)
        }

        files.removeValue(forKey: path)
    }

    /// Create a directory
    public func createDirectory(atPath path: String, withIntermediateDirectories: Bool = false) throws {
        accessHistory.append((path, .createDirectory, Date()))

        if withIntermediateDirectories {
            var components = (path as NSString).pathComponents
            var currentPath = ""
            for component in components {
                currentPath = (currentPath as NSString).appendingPathComponent(component)
                directories.insert(currentPath)
            }
        } else {
            let parentPath = (path as NSString).deletingLastPathComponent
            guard directories.contains(parentPath) else {
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)
            }
            directories.insert(path)
        }
    }

    // MARK: - Access History

    /// Get all file system operations
    public func getAccessHistory() -> [(path: String, operation: Operation, timestamp: Date)] {
        return accessHistory
    }

    /// Get operations for a specific path
    public func getAccessHistory(forPath path: String) -> [(operation: Operation, timestamp: Date)] {
        return accessHistory
            .filter { $0.path == path }
            .map { ($0.operation, $0.timestamp) }
    }

    /// Clear access history
    public func clearHistory() {
        accessHistory.removeAll()
    }

    // MARK: - Preset Configurations

    /// Reset to initial state
    public func reset() {
        files.removeAll()
        directories.removeAll()
        accessHistory.removeAll()

        // Restore default directories
        directories.insert("/")
        directories.insert("/tmp")
        directories.insert("/usr/bin")
        directories.insert("/opt/homebrew/bin")
    }

    /// Setup a mock git executable
    public func setupMockGitExecutable(at path: String = "/usr/bin/git") {
        let parentPath = (path as NSString).deletingLastPathComponent
        if !directories.contains(parentPath) {
            directories.insert(parentPath)
        }
        // Create a placeholder for the executable
        files[path] = Data()
    }

    /// Setup mock Homebrew installation
    public func setupMockHomebrew() {
        directories.insert("/opt/homebrew")
        directories.insert("/opt/homebrew/bin")
        files["/opt/homebrew/bin/git"] = Data()
    }

    /// Setup a temporary test directory
    public func setupTemporaryDirectory(at path: String = "/tmp/test") throws {
        try createDirectory(atPath: path, withIntermediateDirectories: true)
    }
}

// MARK: - Test Helper Extensions

extension MockFileSystem {
    /// Verify that a specific operation was performed on a path
    public func verifyOperation(_ operation: Operation, onPath path: String) -> Bool {
        return accessHistory.contains { $0.path == path && $0.operation == operation }
    }

    /// Count how many times a specific operation was performed
    public func countOperations(_ operation: Operation) -> Int {
        return accessHistory.filter { $0.operation == operation }.count
    }

    /// Get all paths that were accessed
    public func getAccessedPaths() -> [String] {
        return Array(Set(accessHistory.map { $0.path }))
    }
}
