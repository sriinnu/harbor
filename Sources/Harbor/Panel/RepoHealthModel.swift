import Foundation
import HarborCore
import Observation

/// Where the panel finds the signed-in GitHub client without the panel views holding the
/// app state. Set once by `AppState`.
@MainActor
enum RepoHealthService {
    static var client: GitHubClient?
    /// Hands the security section's alert counts to the repo row, so the row and Needs you
    /// show them without the detail asking GitHub a second time.
    static var onAlerts: (@MainActor (_ fullName: String, _ alerts: RepoSecurity, _ epoch: Int) -> Void)?
    /// The account epoch now, so a load can tell its answer belongs to an account that has since gone.
    static var epoch: (@MainActor () -> Int)?
}

/// One repo's health, loaded when its detail opens and thrown away when it closes.
/// In memory only. The three sections load at once and fill in as each arrives.
@MainActor
@Observable
final class RepoHealthModel {
    private(set) var basics: RepoHealthBasics?
    private(set) var security: RepoSecuritySection?
    private(set) var hardening: HardeningChecklist?
    private(set) var flow: RepoFlowSection?
    private(set) var webBase = URL(string: "https://github.com")!
    /// Shown as a quiet note, never a banner. Cancellations never land here.
    private(set) var note: String?
    private(set) var isLoading = true

    private enum Part: Sendable {
        case security(RepoSecuritySection)
        case hardening(HardeningChecklist)
        case flow(RepoFlowSection)
    }

    /// The grade needs the two sections that feed it; flow only adds CI and stale PRs.
    func score(now: Date = Date()) -> RepoHealthScore? {
        guard let basics, let security, let hardening else { return nil }
        return RepoHealthScorer.score(RepoHealthInputs(
            defaultBranch: basics.defaultBranch,
            alerts: security.alerts,
            hasSecurityPolicy: security.hasSecurityPolicy,
            privateReporting: security.privateReporting,
            hardening: hardening,
            latestRunFailing: self.flow?.runs.first.map { $0.status == .failing },
            stalePullRequests: self.flow.map { $0.pulls.count(where: { $0.isStale(now: now) }) }
        ))
    }

    func load(fullName: String) async {
        defer { if !Task.isCancelled { self.isLoading = false } }
        let parts = fullName.split(separator: "/").map(String.init)
        guard parts.count == 2, let client = RepoHealthService.client else { return }
        let (owner, name) = (parts[0], parts[1])
        let epoch = RepoHealthService.epoch?() ?? 0
        do {
            self.webBase = await client.webBase()
            let basics = try await client.repoHealthBasics(owner: owner, name: name)
            self.basics = basics
            await withTaskGroup(of: Result<Part, Error>.self) { group in
                group.addTask { await Result { .security(try await client.repoHealthSecurity(owner: owner, name: name, isAdmin: basics.isAdmin)) } }
                group.addTask { await Result { .hardening(try await client.repoHealthHardening(owner: owner, name: name, basics: basics)) } }
                group.addTask { await Result { .flow(try await client.repoHealthFlow(owner: owner, name: name, basics: basics)) } }
                for await result in group where !Task.isCancelled {
                    self.apply(result)
                    if case let .success(.security(section)) = result { RepoHealthService.onAlerts?(fullName, section.alerts, epoch) }
                }
            }
        } catch {
            self.note = error.reportableMessage
        }
    }

    private func apply(_ result: Result<Part, Error>) {
        switch result {
        case let .success(.security(section)): self.security = section
        case let .success(.hardening(checklist)): self.hardening = checklist
        case let .success(.flow(section)): self.flow = section
        case let .failure(error): if let message = error.reportableMessage { self.note = message }
        }
    }
}

private extension Result where Failure == Error {
    init(_ body: () async throws -> Success) async {
        do { self = try await .success(body()) } catch { self = .failure(error) }
    }
}
