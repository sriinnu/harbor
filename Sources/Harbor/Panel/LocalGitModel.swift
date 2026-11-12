import Foundation
import HarborCore
import Observation

/// What running a command on a clone costs the panel: it runs git, then hands back the
/// clone's fresh status. Set by the menu manager, so the views never touch bookmarks.
typealias LocalGitCommandRunner = @Sendable (LocalGitCommand, URL) async throws -> LocalRepoStatus?

/// One local clone's Git actions: the confirm, the progress and the failure message. In
/// memory only; the panel keeps one per clone while it is open.
@MainActor
@Observable
final class LocalGitModel {
    enum Branches: Equatable {
        case idle
        case loading
        case loaded([String])
        case failed(String)
    }

    let path: URL
    /// The status after the last command, until the session's own status catches up.
    private(set) var fresh: LocalRepoStatus?
    /// The command waiting on an inline confirm.
    var confirming: LocalGitCommand?
    private(set) var running: LocalGitCommand?
    private(set) var error: String?
    private(set) var branches = Branches.idle
    var isPickingBranch = false
    private let runner: LocalGitCommandRunner

    init(path: URL, runner: @escaping LocalGitCommandRunner) {
        self.path = path
        self.runner = runner
    }

    var isBusy: Bool { self.running != nil }
    /// A confirm or a running command: the panel must not close under it.
    var needsPanelOpen: Bool { self.confirming != nil || self.running != nil }

    /// Asks first when the command needs it; otherwise runs at once.
    func request(_ command: LocalGitCommand) {
        guard !self.isBusy else { return }
        self.error = nil
        if command.needsConfirm {
            self.confirming = command
        } else {
            self.perform(command)
        }
    }

    func confirm() {
        guard let command = self.confirming else { return }
        self.confirming = nil
        self.perform(command)
    }

    func cancel() { self.confirming = nil }
    func dismissError() { self.error = nil }

    /// The session's status changed under us (a refresh landed); stop showing the stale one.
    func sessionStatusChanged() {
        if !self.isBusy { self.fresh = nil }
    }

    private func perform(_ command: LocalGitCommand) {
        guard self.running == nil else { return }
        self.running = command
        self.error = nil
        let (path, runner) = (self.path, self.runner)
        Task {
            do {
                let status = try await runner(command, path)
                self.fresh = status ?? self.fresh
                self.isPickingBranch = false
                self.branches = .idle
            } catch {
                if let message = error.reportableMessage { self.error = "\(command.title) failed: \(message)" }
            }
            self.running = nil
        }
    }

    /// The branch picker's list, read from the clone itself (no network) when it opens.
    func loadBranches() async {
        self.branches = .loading
        let path = self.path
        let result = await Task.detached(priority: .userInitiated) {
            Result { try LocalGitService().branches(at: path) }
        }.value
        guard !Task.isCancelled else { return }
        switch result {
        case let .success(list):
            self.branches = .loaded(list.filter { !$0.isCurrent }.map(\.name))
        case let .failure(error):
            self.branches = .failed(error.reportableMessage ?? "Could not read branches.")
        }
    }
}

/// The panel's clone models, by path, so the detail pane and the Needs-you row share one
/// confirm. A plain class on purpose: handing out a model must not invalidate the view.
@MainActor
final class LocalGitHub {
    private var models: [String: LocalGitModel] = [:]
    var runner: LocalGitCommandRunner = { _, _ in nil }

    func model(for path: URL) -> LocalGitModel {
        let key = path.standardizedFileURL.path
        if let existing = self.models[key] { return existing }
        let runner: LocalGitCommandRunner = { [weak self] command, url in
            guard let run = await self?.runner else { return nil }
            return try await run(command, url)
        }
        let model = LocalGitModel(path: path, runner: runner)
        self.models[key] = model
        return model
    }
}
