import AppKit
import HarborCore
import SwiftUI

struct AdvancedSettingsView: View {
    @Bindable var session: Session
    let appState: AppState

    var body: some View {
        Form {
            Section {
                Picker("Refresh interval", selection: self.$session.settings.refreshInterval) {
                    ForEach(RefreshInterval.allCases, id: \.self) { interval in
                        Text(self.intervalLabel(interval)).tag(interval)
                    }
                }
                .onChange(of: self.session.settings.refreshInterval) { _, newValue in
                    LaunchAtLoginHelper.set(enabled: self.session.settings.launchAtLogin)
                    self.appState.persistSettings()
                    Task { @MainActor in
                        self.appState.refreshScheduler.configure(interval: newValue.seconds) { [weak appState] in
                            appState?.requestRefresh()
                        }
                    }
                }
            } header: {
                Text("Refresh")
            } footer: {
                Text("Controls how often Harbor refreshes GitHub data.")
            }

            Section {
                LabeledContent("Project folder") {
                    HStack(spacing: 8) {
                        Text(self.projectFolderLabel)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(self.projectFolderLabelColor)
                        Button("Choose…") { self.pickProjectFolder() }
                        if self.session.settings.localProjects.rootPath != nil {
                            Button {
                                self.appState.refreshLocalProjects(forceRescan: true)
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                            .help("Rescan local projects")
                            Button {
                                self.clearProjectFolder()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Clear project folder")
                        }
                    }
                }

                if let summary = self.localRepoSummary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("Auto-sync clean repos", isOn: self.$session.settings.localProjects.autoSyncEnabled)
                    .disabled(self.session.settings.localProjects.rootPath == nil)
                    .onChange(of: self.session.settings.localProjects.autoSyncEnabled) { _, _ in
                        self.appState.persistSettings()
                        self.appState.refreshLocalProjects()
                        self.appState.requestRefresh(cancelInFlight: true)
                    }

                Toggle("Show dirty files in menu", isOn: self.$session.settings.localProjects.showDirtyFilesInMenu)
                    .disabled(self.session.settings.localProjects.rootPath == nil)
                    .onChange(of: self.session.settings.localProjects.showDirtyFilesInMenu) { _, _ in
                        self.appState.persistSettings()
                        NotificationCenter.default.post(name: .menuFiltersDidChange, object: nil)
                    }

                HStack {
                    Text("Worktree folder")
                    Spacer()
                    TextField("", text: self.worktreeFolderBinding)
                        .frame(width: 120)
                        .multilineTextAlignment(.trailing)
                        .disabled(self.session.settings.localProjects.rootPath == nil)
                }

                HStack {
                    Text("Fetch interval")
                    Spacer()
                    Picker("", selection: self.$session.settings.localProjects.fetchInterval) {
                        ForEach(LocalProjectsRefreshInterval.allCases, id: \.self) { interval in
                            Text(interval.label).tag(interval)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .disabled(self.session.settings.localProjects.rootPath == nil)
                    .onChange(of: self.session.settings.localProjects.fetchInterval) { _, _ in
                        self.appState.persistSettings()
                        self.appState.refreshLocalProjects()
                    }
                }

                HStack {
                    Text("Preferred Terminal")
                    Spacer()
                    Picker("", selection: self.preferredTerminalBinding) {
                        ForEach(TerminalApp.installed, id: \.rawValue) { terminal in
                            HStack {
                                if let icon = terminal.appIcon {
                                    Image(nsImage: icon.resized(to: NSSize(width: 16, height: 16)))
                                }
                                Text(terminal.displayName)
                            }
                            .tag(terminal.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .disabled(self.session.settings.localProjects.rootPath == nil)
                }

                if self.isGhosttySelected {
                    HStack {
                        Text("Ghostty opens in")
                        Spacer()
                        Picker("", selection: self.ghosttyOpenModeBinding) {
                            ForEach(GhosttyOpenMode.allCases, id: \.self) { mode in
                                Text(mode.label)
                                    .tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .disabled(self.session.settings.localProjects.rootPath == nil)
                    }
                }
            } header: {
                Text("Local Projects")
            } footer: {
                Text("Scans two levels deep under the folder, fetches periodically, and can fast-forward pull clean repos.")
            }

            Section {
                LabeledContent("Token Storage") {
                    HStack(spacing: 6) {
                        Image(systemName: self.tokenStorageStatusIcon)
                            .foregroundStyle(self.tokenStorageStatusColor)
                        Text(self.tokenStorageStatus)
                            .foregroundStyle(.secondary)
                    }
                }

                if let gitPath = self.gitExecutablePath {
                    LabeledContent("Git Executable") {
                        Text(gitPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(gitPath)
                    }
                } else {
                    LabeledContent("Git Executable") {
                        Text("Not found")
                            .foregroundStyle(.orange)
                    }
                }

                Toggle("Platform services logging", isOn: self.$session.settings.diagnosticsEnabled)
                    .onChange(of: self.session.settings.diagnosticsEnabled) { _, enabled in
                        self.appState.persistSettings()
                        Task { await DiagnosticsLogger.shared.setEnabled(enabled) }
                    }
            } header: {
                Text("Platform Services")
            } footer: {
                Text("Platform abstraction layer provides cross-platform token storage, OAuth callbacks, and executable discovery.")
            }

            #if DEBUG
                Section {
                    Toggle("Enable debug tools", isOn: self.$session.settings.debugPaneEnabled)
                        .onChange(of: self.session.settings.debugPaneEnabled) { _, _ in
                            self.appState.persistSettings()
                        }
                } header: {
                    Text("Debug")
                } footer: {
                    Text("Developer-only diagnostics and experimental tools.")
                }
            #endif
        }
        .formStyle(.grouped)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .onAppear {
            self.ensurePreferredTerminal()
            self.appState.refreshLocalProjects()
        }
    }

    private func intervalLabel(_ interval: RefreshInterval) -> String {
        switch interval {
        case .oneMinute: "1 minute"
        case .twoMinutes: "2 minutes"
        case .fiveMinutes: "5 minutes"
        case .fifteenMinutes: "15 minutes"
        }
    }

    private var projectFolderLabel: String {
        guard let path = self.session.settings.localProjects.rootPath,
              path.isEmpty == false
        else { return "Not set" }
        return PathFormatter.displayString(path)
    }

    private var projectFolderLabelColor: Color {
        self.session.settings.localProjects.rootPath == nil ? .secondary : .primary
    }

    private var localRepoSummary: String? {
        guard self.session.settings.localProjects.rootPath != nil else { return nil }
        if self.session.localProjectsScanInProgress { return "Scanning…" }
        let total = self.session.localDiscoveredRepoCount
        let matched = self.localMatchedRepoCount
        if total == 0 {
            if self.session.localProjectsAccessDenied || self.session.settings.localProjects.rootBookmarkData == nil {
                return "No repositories found yet. Re-choose the folder to grant access."
            }
            return "No repositories found yet."
        }
        if matched > 0 { return "Found \(total) local repos · \(matched) match GitHub data." }
        return "Found \(total) local repos."
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

    // Platform Services Status
    private var tokenStorageStatus: String {
        do {
            let hasTokens = try self.appState.platform.tokenStorage.load() != nil
            return hasTokens ? "Active (tokens stored)" : "Active (no tokens)"
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    private var tokenStorageStatusIcon: String {
        do {
            let hasTokens = try self.appState.platform.tokenStorage.load() != nil
            return hasTokens ? "key.fill" : "key"
        } catch {
            return "exclamationmark.triangle.fill"
        }
    }

    private var tokenStorageStatusColor: Color {
        do {
            let hasTokens = try self.appState.platform.tokenStorage.load() != nil
            return hasTokens ? .green : .secondary
        } catch {
            return .orange
        }
    }

    private var gitExecutablePath: String? {
        #if os(macOS)
        if let gitURL = try? self.appState.platform.executableLocator.locate(executable: "git") {
            return gitURL.path
        }
        #endif
        return nil
    }
}
