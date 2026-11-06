import Foundation
@testable import HarborCore
import Testing

struct ExecutableLocatorTests {
    // MARK: - MockExecutableLocator Tests

    @Test
    func mockLocatorReturnsConfiguredPath() {
        let locator = MockExecutableLocator(path: "/usr/bin/git")
        let result = locator.locate(executable: "git")
        #expect(result?.path == "/usr/bin/git")
    }

    @Test
    func mockLocatorReturnsNilWhenPathIsNil() {
        let locator = MockExecutableLocator(path: nil)
        let result = locator.locate(executable: "git")
        #expect(result == nil)
    }

    @Test
    func mockLocatorReturnsConfiguredVersion() {
        let locator = MockExecutableLocator(
            path: "/usr/bin/git",
            version: "git version 2.42.0"
        )
        let url = URL(fileURLWithPath: "/usr/bin/git")
        let (version, error) = locator.version(at: url)
        #expect(version == "git version 2.42.0")
        #expect(error == nil)
    }

    @Test
    func mockLocatorReturnsConfiguredError() {
        let locator = MockExecutableLocator(
            path: "/usr/bin/git",
            version: nil,
            error: "Command not found"
        )
        let url = URL(fileURLWithPath: "/usr/bin/git")
        let (version, error) = locator.version(at: url)
        #expect(version == nil)
        #expect(error == "Command not found")
    }

    @Test
    func mockLocatorReturnsConfiguredSandboxStatus() {
        let sandboxed = MockExecutableLocator(isSandboxed: true)
        #expect(sandboxed.isSandboxed == true)

        let notSandboxed = MockExecutableLocator(isSandboxed: false)
        #expect(notSandboxed.isSandboxed == false)
    }

    // MARK: - macOS ExecutableLocator Tests

    #if os(macOS)
    @Test
    func macOSLocatorCanFindGit() {
        let locator = MacOSExecutableLocator()
        let result = locator.locate(executable: "git")
        // Git should be available on macOS (either via Xcode or Homebrew)
        #expect(result != nil)
        if let gitPath = result?.path {
            #expect(FileManager.default.fileExists(atPath: gitPath))
        }
    }

    @Test
    func macOSLocatorReturnsNilForNonexistentExecutable() {
        let locator = MacOSExecutableLocator()
        let result = locator.locate(executable: "definitely-does-not-exist-12345")
        #expect(result == nil)
    }

    @Test
    func macOSLocatorCanGetGitVersion() {
        let locator = MacOSExecutableLocator()
        guard let gitURL = locator.locate(executable: "git") else {
            Issue.record("Git not found on system")
            return
        }
        let (version, error) = locator.version(at: gitURL)
        #expect(error == nil)
        #expect(version != nil)
        #expect(version?.lowercased().contains("git") == true)
    }

    @Test
    func macOSLocatorHandlesInvalidExecutable() {
        let locator = MacOSExecutableLocator()
        let invalidURL = URL(fileURLWithPath: "/tmp/nonexistent-binary-12345")
        let (version, error) = locator.version(at: invalidURL)
        #expect(version == nil)
        #expect(error != nil)
    }

    @Test
    func macOSLocatorDetectsSandboxStatus() {
        let locator = MacOSExecutableLocator()
        // In tests, the app is typically not sandboxed
        // This test just verifies the property is accessible
        _ = locator.isSandboxed
        // We don't assert a specific value since it depends on the test environment
    }
    #endif

    // MARK: - Linux ExecutableLocator Tests

    #if os(Linux)
    @Test
    func posixLocatorCanFindGit() {
        let locator = POSIXExecutableLocator()
        let result = locator.locate(executable: "git")
        // Git should be available on most Linux systems
        #expect(result != nil)
        if let gitPath = result?.path {
            #expect(FileManager.default.fileExists(atPath: gitPath))
        }
    }

    @Test
    func posixLocatorReturnsNilForNonexistentExecutable() {
        let locator = POSIXExecutableLocator()
        let result = locator.locate(executable: "definitely-does-not-exist-12345")
        #expect(result == nil)
    }

    @Test
    func posixLocatorCanGetGitVersion() {
        let locator = POSIXExecutableLocator()
        guard let gitURL = locator.locate(executable: "git") else {
            Issue.record("Git not found on system")
            return
        }
        let (version, error) = locator.version(at: gitURL)
        #expect(error == nil)
        #expect(version != nil)
        #expect(version?.lowercased().contains("git") == true)
    }

    @Test
    func posixLocatorIsNotSandboxed() {
        let locator = POSIXExecutableLocator()
        // Linux typically doesn't use sandboxing
        #expect(locator.isSandboxed == false)
    }
    #endif

    // MARK: - Integration Tests

    @Test
    func locatorWorksWithLocalProjectsService() {
        let locator = MockExecutableLocator(
            path: "/usr/bin/git",
            version: "git version 2.42.0"
        )
        let service = LocalProjectsService(executableLocator: locator)
        let info = service.gitExecutableInfo()
        #expect(info.path == "/usr/bin/git")
        #expect(info.version == "git version 2.42.0")
    }

    @Test
    func locatorReturnsNotFoundWhenGitMissing() {
        let locator = MockExecutableLocator(path: nil)
        let service = LocalProjectsService(executableLocator: locator)
        let info = service.gitExecutableInfo()
        #expect(info.path == "not found")
        #expect(info.error == "Git executable not found")
    }
}
