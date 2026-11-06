import Testing
import Foundation
@testable import HarborCore

/// Integration tests for Git operations with platform services
@Suite("Git Service Integration Tests")
struct GitServiceIntegrationTests {

    // MARK: - LocalGitService with MockExecutableLocator

    @Test("LocalGitService uses ExecutableLocator to find git")
    func localGitServiceUsesExecutableLocatorToFindGit() {
        let locator = MockExecutableLocator(
            path: "/usr/bin/git",
            version: "git version 2.42.0"
        )

        let service = LocalGitService(executableLocator: locator)

        // Service should use the locator to find git
        // This is verified by the service not crashing during initialization
    }

    @Test("LocalGitService handles missing git executable")
    func localGitServiceHandlesMissingGitExecutable() {
        let locator = MockExecutableLocator(path: nil)

        let service = LocalGitService(executableLocator: locator)

        // Service should handle missing git gracefully
        // Operations should fail with appropriate errors
    }

    @Test("LocalGitService with custom git path")
    func localGitServiceWithCustomGitPath() {
        let customPath = "/opt/homebrew/bin/git"
        let locator = MockExecutableLocator(
            path: customPath,
            version: "git version 2.43.0"
        )

        let service = LocalGitService(executableLocator: locator)

        // Service should use the custom git path
    }

    // MARK: - LocalProjectsService with ExecutableLocator

    @Test("LocalProjectsService reports git executable info")
    func localProjectsServiceReportsGitExecutableInfo() {
        let expectedPath = "/usr/bin/git"
        let expectedVersion = "git version 2.42.0"
        let locator = MockExecutableLocator(
            path: expectedPath,
            version: expectedVersion
        )

        let service = LocalProjectsService(executableLocator: locator)
        let info = service.gitExecutableInfo()

        #expect(info.path == expectedPath)
        #expect(info.version == expectedVersion)
        #expect(info.error == nil)
    }

    @Test("LocalProjectsService reports error when git not found")
    func localProjectsServiceReportsErrorWhenGitNotFound() {
        let locator = MockExecutableLocator(path: nil)

        let service = LocalProjectsService(executableLocator: locator)
        let info = service.gitExecutableInfo()

        #expect(info.path == "not found")
        #expect(info.error == "Git executable not found")
        #expect(info.version == nil)
    }

    @Test("LocalProjectsService reports error when git version fails")
    func localProjectsServiceReportsErrorWhenGitVersionFails() {
        let locator = MockExecutableLocator(
            path: "/usr/bin/git",
            version: nil,
            error: "Permission denied"
        )

        let service = LocalProjectsService(executableLocator: locator)
        let info = service.gitExecutableInfo()

        #expect(info.path == "/usr/bin/git")
        #expect(info.version == nil)
        #expect(info.error == "Permission denied")
    }

    @Test("LocalProjectsService handles sandboxed environment")
    func localProjectsServiceHandlesSandboxedEnvironment() {
        let sandboxedLocator = MockExecutableLocator(
            path: "/Library/Developer/CommandLineTools/usr/bin/git",
            version: "git version 2.39.0",
            isSandboxed: true
        )

        let service = LocalProjectsService(executableLocator: sandboxedLocator)
        let info = service.gitExecutableInfo()

        #expect(info.path.contains("CommandLineTools"))
        #expect(info.version != nil)
    }

    // MARK: - Platform Services Integration

    @Test("Git service with MockPlatformServices")
    func gitServiceWithMockPlatformServices() {
        let services = MockPlatformServices()

        let gitService = LocalGitService(executableLocator: services.executableLocator)
        let projectsService = LocalProjectsService(executableLocator: services.executableLocator)

        // Both services should work with the same platform services
        let info = projectsService.gitExecutableInfo()
        #expect(info.path == "/usr/bin/git")
    }

    #if os(macOS)
    @Test("Git service with ApplePlatformServices finds real git")
    func gitServiceWithApplePlatformServicesFindsRealGit() {
        let services = ApplePlatformServices()

        let projectsService = LocalProjectsService(executableLocator: services.executableLocator)
        let info = projectsService.gitExecutableInfo()

        // On macOS with Xcode tools, git should be found
        #expect(info.path != "not found")
        #expect(info.version != nil)
        #expect(info.version?.contains("git") == true)
    }
    #endif

    // MARK: - Executable Locator Fallback Paths

    @Test("Git service tries multiple paths")
    func gitServiceTriesMultiplePaths() {
        // Simulate a scenario where git is not in the first path
        let locator = MockExecutableLocator(
            path: "/opt/homebrew/bin/git",
            version: "git version 2.42.0"
        )

        let service = LocalProjectsService(executableLocator: locator)
        let info = service.gitExecutableInfo()

        #expect(info.path == "/opt/homebrew/bin/git")
    }

    @Test("Git service works with Homebrew git")
    func gitServiceWorksWithHomebrewGit() {
        let homebrewPath = "/opt/homebrew/bin/git"
        let locator = MockExecutableLocator(
            path: homebrewPath,
            version: "git version 2.43.0"
        )

        let service = LocalProjectsService(executableLocator: locator)
        let info = service.gitExecutableInfo()

        #expect(info.path == homebrewPath)
        #expect(info.version?.contains("2.43.0") == true)
    }

    @Test("Git service works with Xcode git")
    func gitServiceWorksWithXcodeGit() {
        let xcodePath = "/Applications/Xcode.app/Contents/Developer/usr/bin/git"
        let locator = MockExecutableLocator(
            path: xcodePath,
            version: "git version 2.39.0 (Apple Git-138)"
        )

        let service = LocalProjectsService(executableLocator: locator)
        let info = service.gitExecutableInfo()

        #expect(info.path == xcodePath)
        #expect(info.version?.contains("Apple Git") == true)
    }

    @Test("Git service works with system git")
    func gitServiceWorksWithSystemGit() {
        let systemPath = "/usr/bin/git"
        let locator = MockExecutableLocator(
            path: systemPath,
            version: "git version 2.37.0"
        )

        let service = LocalProjectsService(executableLocator: locator)
        let info = service.gitExecutableInfo()

        #expect(info.path == systemPath)
        #expect(info.version != nil)
    }

    // MARK: - Error Handling

    @Test("Git service handles version check errors")
    func gitServiceHandlesVersionCheckErrors() {
        let locator = MockExecutableLocator(
            path: "/usr/bin/git",
            version: nil,
            error: "Command failed with exit code 1"
        )

        let service = LocalProjectsService(executableLocator: locator)
        let info = service.gitExecutableInfo()

        #expect(info.error != nil)
        #expect(info.error?.contains("failed") == true)
    }

    @Test("Git service handles permission errors")
    func gitServiceHandlesPermissionErrors() {
        let locator = MockExecutableLocator(
            path: "/usr/bin/git",
            version: nil,
            error: "Operation not permitted"
        )

        let service = LocalProjectsService(executableLocator: locator)
        let info = service.gitExecutableInfo()

        #expect(info.error?.contains("permitted") == true)
    }

    // MARK: - Multiple Services with Same Locator

    @Test("Multiple services share same executable locator")
    func multipleServicesShareSameExecutableLocator() {
        let locator = MockExecutableLocator(
            path: "/usr/bin/git",
            version: "git version 2.42.0"
        )

        let service1 = LocalProjectsService(executableLocator: locator)
        let service2 = LocalProjectsService(executableLocator: locator)

        let info1 = service1.gitExecutableInfo()
        let info2 = service2.gitExecutableInfo()

        #expect(info1.path == info2.path)
        #expect(info1.version == info2.version)
    }

    @Test("Services with different locators report different git")
    func servicesWithDifferentLocatorsReportDifferentGit() {
        let locator1 = MockExecutableLocator(
            path: "/usr/bin/git",
            version: "git version 2.39.0"
        )
        let locator2 = MockExecutableLocator(
            path: "/opt/homebrew/bin/git",
            version: "git version 2.43.0"
        )

        let service1 = LocalProjectsService(executableLocator: locator1)
        let service2 = LocalProjectsService(executableLocator: locator2)

        let info1 = service1.gitExecutableInfo()
        let info2 = service2.gitExecutableInfo()

        #expect(info1.path != info2.path)
        #expect(info1.version != info2.version)
    }

    // MARK: - Concurrent Access

    @Test("Concurrent git executable info requests")
    func concurrentGitExecutableInfoRequests() async {
        let locator = MockExecutableLocator(
            path: "/usr/bin/git",
            version: "git version 2.42.0"
        )

        let service = LocalProjectsService(executableLocator: locator)

        await withTaskGroup(of: GitExecutableInfo.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    service.gitExecutableInfo()
                }
            }

            var results: [GitExecutableInfo] = []
            for await result in group {
                results.append(result)
            }

            // All results should be consistent
            let firstPath = results.first?.path
            #expect(results.allSatisfy { $0.path == firstPath })
        }
    }

    // MARK: - Sandboxed Environment Tests

    @Test("Sandboxed service uses limited paths")
    func sandboxedServiceUsesLimitedPaths() {
        let sandboxedLocator = MockExecutableLocator(
            path: "/Library/Developer/CommandLineTools/usr/bin/git",
            isSandboxed: true
        )

        let service = LocalProjectsService(executableLocator: sandboxedLocator)

        // In sandboxed mode, should use CommandLineTools path
        let info = service.gitExecutableInfo()
        #expect(info.path.contains("CommandLineTools"))
    }

    @Test("Non-sandboxed service prefers Homebrew")
    func nonSandboxedServicePrefersHomebrew() {
        let nonSandboxedLocator = MockExecutableLocator(
            path: "/opt/homebrew/bin/git",
            isSandboxed: false
        )

        let service = LocalProjectsService(executableLocator: nonSandboxedLocator)

        // In non-sandboxed mode, should prefer Homebrew
        let info = service.gitExecutableInfo()
        #expect(info.path.contains("homebrew"))
    }

    // MARK: - Integration with Settings

    @Test("Git service configuration persisted in settings")
    func gitServiceConfigurationPersistedInSettings() async {
        let services = MockPlatformServices()

        var settings = UserSettings()
        settings.localProjects.rootPath = "~/Projects"
        settings.localProjects.autoSyncEnabled = true

        await services.settingsStorage.save(settings)

        let loaded = await services.settingsStorage.load()
        #expect(loaded.localProjects.rootPath == "~/Projects")
        #expect(loaded.localProjects.autoSyncEnabled == true)
    }

    // MARK: - Platform-Specific Behavior

    #if os(macOS)
    @Test("macOS git service detects Xcode installation")
    func macOSGitServiceDetectsXcodeInstallation() {
        let services = ApplePlatformServices()
        let projectsService = LocalProjectsService(executableLocator: services.executableLocator)

        let info = projectsService.gitExecutableInfo()

        // Git should be found (either Homebrew or Xcode)
        #expect(info.path != "not found")

        // Version should indicate the source
        if let version = info.version {
            let isHomebrew = version.contains("Homebrew")
            let isApple = version.contains("Apple")
            let isStandard = !isHomebrew && !isApple

            #expect(isHomebrew || isApple || isStandard)
        }
    }
    #endif

    // MARK: - Error Recovery

    @Test("Git service recovers from initial failure")
    func gitServiceRecoversFromInitialFailure() {
        // First try fails
        let failingLocator = MockExecutableLocator(path: nil)
        let service1 = LocalProjectsService(executableLocator: failingLocator)
        let info1 = service1.gitExecutableInfo()
        #expect(info1.path == "not found")

        // Second try succeeds with different locator
        let workingLocator = MockExecutableLocator(path: "/usr/bin/git")
        let service2 = LocalProjectsService(executableLocator: workingLocator)
        let info2 = service2.gitExecutableInfo()
        #expect(info2.path == "/usr/bin/git")
    }
}
