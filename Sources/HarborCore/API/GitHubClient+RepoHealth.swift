import Foundation

/// The repo detail's health card, one section per call so the panel can fill in as each
/// arrives. Nothing is cached to disk.
public extension GitHubClient {
    func repoHealthBasics(owner: String, name: String) async throws -> RepoHealthBasics {
        try await self.restAPI.healthBasics(owner: owner, name: name)
    }

    /// `isAdmin` comes from `repoHealthBasics`: for an admin a code-scanning 403 means
    /// "not enabled", not "needs admin".
    func repoHealthSecurity(owner: String, name: String, isAdmin: Bool?) async throws -> RepoSecuritySection {
        try await self.restAPI.healthSecurity(owner: owner, name: name, isAdmin: isAdmin)
    }

    func repoHealthHardening(owner: String, name: String, basics: RepoHealthBasics) async throws -> HardeningChecklist {
        try await self.restAPI.healthHardening(owner: owner, name: name, basics: basics)
    }

    func repoHealthFlow(owner: String, name: String, basics: RepoHealthBasics) async throws -> RepoFlowSection {
        let release = try? await self.restAPI.latestReleaseAny(owner: owner, name: name)
        return try await self.restAPI.healthFlow(owner: owner, name: name, basics: basics, release: release)
    }

    /// Where the web UI lives for this API host, for the settings links.
    func webBase() -> URL { RepoSettingsURL.webBase(fromAPIHost: self.apiHost) }
}

/// "Clean up old runs": list what is there, then delete one run at a time so the caller
/// can show progress and stop on the first error.
public extension GitHubClient {
    func cleanupCandidates(owner: String, name: String) async throws -> RunCleanup.Plan {
        let api = self.restAPI
        async let workflows = api.listWorkflows(owner: owner, name: name)
        async let runs = api.listWorkflowRuns(owner: owner, name: name)
        return try await RunCleanup.plan(workflows: workflows, runs: runs)
    }

    func deleteWorkflowRun(owner: String, name: String, id: Int) async throws {
        try await self.restAPI.deleteWorkflowRun(owner: owner, name: name, id: id)
    }
}
