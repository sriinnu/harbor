import AppKit
import HarborCore
import SwiftUI

/// Local clones: where they live, how Harbor keeps them current, and how it opens them.
struct LocalGitSettingsView: View {
    @Bindable var session: Session
    let appState: AppState

    private var hasFolder: Bool {
        self.session.settings.localProjects.rootPath != nil
    }

    var body: some View {
        SettingsPane {
            Section {
                LabeledContent {
                    HStack(spacing: 6) {
                        if self.hasFolder {
                            Button {
                                self.appState.refreshLocalProjects(forceRescan: true)
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                            .help("Rescan the projects folder")
                            .accessibilityLabel("Rescan projects folder")

                            Button {
                                self.clearProjectFolder()
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Stop using this folder")
                            .accessibilityLabel("Clear projects folder")
                        }
                        Button(self.hasFolder ? "Change…" : "Choose…") { self.pickProjectFolder() }
                    }
                } label: {
                    Text(verbatim: self.projectFolderLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(self.session.settings.localProjects.rootPath ?? "")
                    if let summary = self.localRepoSummary {
                        Text(verbatim: summary)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Projects folder")
            } header: {
                Text("Projects folder")
            } footer: {
                SettingsFooter("Harbor looks two levels deep for Git repositories and matches them to your remote repositories.")
            }

            Section {
                Toggle(isOn: self.$session.settings.localProjects.autoSyncEnabled) {
                    SettingsLabel(title: "Fast-forward clean repositories", detail: "Pulls with --ff-only when the working tree is clean.")
                }
                .onChange(of: self.session.settings.localProjects.autoSyncEnabled) { _, _ in
                    self.appState.persistSettings()
                    self.appState.refreshLocalProjects()
                    self.appState.requestRefresh(cancelInFlight: true)
                }

                Picker("Fetch every", selection: self.$session.settings.localProjects.fetchInterval) {
                    ForEach(LocalProjectsRefreshInterval.allCases, id: \.self) { interval in
                        Text(interval.label).tag(interval)
                    }
                }
                .onChange(of: self.session.settings.localProjects.fetchInterval) { _, _ in
                    self.appState.persistSettings()
                    self.appState.refreshLocalProjects()
                }

                Toggle("Show changed files in the menu", isOn: self.$session.settings.localProjects.showDirtyFilesInMenu)
                    .onChange(of: self.session.settings.localProjects.showDirtyFilesInMenu) { _, _ in
                        self.appState.persistSettings()
                        NotificationCenter.default.post(name: .menuFiltersDidChange, object: nil)
                    }
            } header: {
                Text("Sync")
            } footer: {
                SettingsFooter("Harbor never merges, rebases or stashes for you. Dirty or diverged branches are left alone.")
            }
            .disabled(!self.hasFolder)

            Section {
                Picker("Terminal", selection: self.preferredTerminalBinding) {
                    ForEach(TerminalApp.installed, id: \.rawValue) { terminal in
                        Label {
                            Text(terminal.displayName)
                        } icon: {
                            if let icon = terminal.appIcon {
                                Image(nsImage: icon.resized(to: NSSize(width: 16, height: 16)))
                            }
                        }
                        .tag(terminal.rawValue)
                    }
                }

                if self.isGhosttySelected {
                    Picker("Ghostty opens in", selection: self.ghosttyOpenModeBinding) {
                        ForEach(GhosttyOpenMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                }

                LabeledContent {
                    TextField("Worktree folder", text: self.worktreeFolderBinding, prompt: Text(verbatim: ".work"))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 140)
                } label: {
                    SettingsLabel(title: "Worktree folder", detail: "Created inside each repository for new worktrees.")
                }
            } header: {
                Text("Open in")
            }
            .disabled(!self.hasFolder)

            Section {
                LabeledContent("Executable") {
                    if let gitPath = self.gitExecutablePath {
                        Text(verbatim: gitPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .help(gitPath)
                    } else {
                        SettingsStatus(text: "Not found", kind: .warning)
                    }
                }
            } header: {
                Text("Git")
            } footer: {
                SettingsFooter("Harbor uses your Git, with your ~/.gitconfig and SSH keys.")
            }
        }
        .onAppear {
            self.ensurePreferredTerminal()
            self.appState.refreshLocalProjects()
        }
    }

    // MARK: - Labels

    private var projectFolderLabel: String {
        guard let path = self.session.settings.localProjects.rootPath,
              path.isEmpty == false
        else { return "No folder chosen" }
        return PathFormatter.displayString(path)
    }

    private var localRepoSummary: String? {
        guard self.hasFolder else { return "Choose the folder where you keep your clones." }
        if self.session.localProjectsScanInProgress { return "Scanning…" }
        let total = self.session.localDiscoveredRepoCount
        let matched = self.localMatchedRepoCount
        if total == 0 {
            if self.session.localProjectsAccessDenied || self.session.settings.localProjects.rootBookmarkData == nil {
                return "No repositories found yet. Choose the folder again to grant access."
            }
            return "No repositories found yet."
        }
        let noun = total == 1 ? "repository" : "repositories"
        if matched > 0 { return "\(total) local \(noun) · \(matched) matched to remote data" }
        return "\(total) local \(noun)"
    }

    private var localMatchedRepoCount: Int {
        let repos = self.session.repositories.isEmpty
            ? (self.session.menuSnapshot?.repositories ?? [])
            : self.session.repositories
        guard repos.isEmpty == false else { return 0 }
        let fullNames = Set(repos.map(\.fullName))
        let repoByName = Dictionary(grouping: repos, by: \.name)
        var matched = 0
        for status in self.session.localRepoIndex.all {
            if let fullName = status.fullName, fullNames.contains(fullName) {
                matched += 1
            } else if let candidates = repoByName[status.name], candidates.count == 1 {
                matched += 1
            }
        }
        return matched
    }

    private var gitExecutablePath: String? {
        self.appState.platform.executableLocator.locate(executable: "git")?.path
    }

    // MARK: - Bindings

    private var preferredTerminalBinding: Binding<String> {
        Binding(
            get: {
                self.session.settings.localProjects.preferredTerminal ?? TerminalApp.defaultPreferred.rawValue
            },
            set: { newValue in
                self.session.settings.localProjects.preferredTerminal = newValue
                self.appState.persistSettings()
            }
        )
    }

    private var ghosttyOpenModeBinding: Binding<GhosttyOpenMode> {
        Binding(
            get: { self.session.settings.localProjects.ghosttyOpenMode },
            set: { newValue in
                self.session.settings.localProjects.ghosttyOpenMode = newValue
                self.appState.persistSettings()
            }
        )
    }

    private var isGhosttySelected: Bool {
        TerminalApp.resolve(self.session.settings.localProjects.preferredTerminal) == .ghostty
    }

    private var worktreeFolderBinding: Binding<String> {
        Binding(
            get: {
                self.session.settings.localProjects.worktreeFolderName
            },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                self.session.settings.localProjects.worktreeFolderName = trimmed.isEmpty ? ".work" : trimmed
                self.appState.persistSettings()
            }
        )
    }

    // MARK: - Actions

    private func pickProjectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if let existing = self.session.settings.localProjects.rootPath {
            panel.directoryURL = URL(fileURLWithPath: PathFormatter.expandTilde(existing), isDirectory: true)
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            panel.directoryURL = home.appendingPathComponent("Projects", isDirectory: true)
        }
        if panel.runModal() == .OK, let url = panel.url {
            let filePathURL = (url as NSURL).filePathURL ?? url
            let resolvedPath = filePathURL.resolvingSymlinksInPath().path
            self.session.settings.localProjects.rootPath = PathFormatter.abbreviateHome(resolvedPath)
            self.session.settings.localProjects.rootBookmarkData = SecurityScopedBookmark.create(for: url)
            self.appState.persistSettings()
            self.appState.refreshLocalProjects(forceRescan: true)
            self.appState.requestRefresh(cancelInFlight: true)
        }
    }

    private func clearProjectFolder() {
        self.session.settings.localProjects.rootPath = nil
        self.session.settings.localProjects.rootBookmarkData = nil
        self.appState.persistSettings()
        self.appState.refreshLocalProjects(forceRescan: true)
        self.appState.requestRefresh(cancelInFlight: true)
    }

    private func ensurePreferredTerminal() {
        let resolved = TerminalApp.resolve(self.session.settings.localProjects.preferredTerminal).rawValue
        if self.session.settings.localProjects.preferredTerminal != resolved {
            self.session.settings.localProjects.preferredTerminal = resolved
            self.appState.persistSettings()
        }
    }
}
