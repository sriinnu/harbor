import HarborCore
import SwiftUI

struct RepoSettingsView: View {
    @Bindable var session: Session
    let appState: AppState
    @State private var newRepoInput = ""
    @State private var newRepoVisibility: RepoVisibility = .pinned
    @State private var selection = Set<String>()
    /// Off: the picker suggests only your repos (yours, your orgs', collaborations).
    @State private var includePublic = false

    var body: some View {
        SettingsPane {
            Section {
                RepoInputRow(
                    placeholder: "owner/name",
                    buttonTitle: "Add",
                    text: self.$newRepoInput,
                    onCommit: self.addNewRepo,
                    session: self.session,
                    appState: self.appState,
                    includePublic: self.includePublic
                ) {
                    Picker("Add as", selection: self.$newRepoVisibility) {
                        ForEach([RepoVisibility.pinned, .hidden], id: \.id) { vis in
                            Text(vis.label).tag(vis)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityLabel("Add as")
                }
            } header: {
                // The checkbox sits above the field: the suggestion list opens below it and
                // would cover anything there.
                HStack(alignment: .firstTextBaseline) {
                    Text("Add a repository")
                    Spacer(minLength: 8)
                    Toggle("Include public repos", isOn: self.$includePublic)
                        .toggleStyle(.checkbox)
                        .font(.body)
                        .help("Also search every public repository on GitHub, listed after yours")
                }
            } footer: {
                SettingsFooter("Search your GitHub repositories (yours and your organizations') and your Azure DevOps organization's by name. Type owner/name for GitHub, or pick an Azure repo from the list.")
            }

            Section {
                if self.rows.isEmpty {
                    Text("Nothing pinned or hidden yet. Pinned repositories stay at the top of the menu; hidden ones never show.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 6)
                } else {
                    self.table
                }
            } header: {
                Text(self.listHeader)
            } footer: {
                if !self.rows.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Button("Remove", role: .destructive) { self.deleteSelection() }
                            .disabled(self.selection.isEmpty)
                            .help("Return the selected repositories to the normal list")
                        Text("Removing returns a repository to the normal list. Right-click for more.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .onAppear {
            Task { try? await self.appState.github.prefetchedRepositories() }
        }
    }

    /// A stored Azure DevOps key reads as `org / project / repo · Azure`; GitHub names as stored.
    static func readable(_ stored: String) -> String {
        guard case let .azure(_, organization, project, name) = RepoKey(stored) else { return stored }
        return "\(organization) / \(project) / \(name) · Azure"
    }

    private var listHeader: String {
        let pinned = self.session.settings.repoList.pinnedRepositories.count
        let hidden = self.rows.count - pinned
        return "Pinned \(pinned) · Hidden \(hidden)"
    }

    private var table: some View {
        Table(self.rows, selection: self.$selection) {
            TableColumn("Repository") { row in
                Text(Self.readable(row.name)).lineLimit(1).truncationMode(.middle).help(row.name)
            }
            .width(min: 180, ideal: 260, max: .infinity)

            TableColumn("Shown as") { row in
                Picker("Visibility of \(row.name)", selection: Binding(
                    get: { row.visibility },
                    set: { newValue in Task { await self.set(row.name, to: newValue) } }
                )) {
                    ForEach(RepoVisibility.allCases) { vis in
                        Text(vis.label).tag(vis)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            .width(min: 110, ideal: 130, max: 150)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .scrollContentBackground(.hidden)
        .frame(height: 260)
        .onDeleteCommand { self.deleteSelection() }
        .contextMenu(forSelectionType: String.self) { selection in
            Button("Pin") { Task { await self.bulkSet(selection, to: .pinned) } }
            Button("Hide") { Task { await self.bulkSet(selection, to: .hidden) } }
            Divider()
            Button("Remove") { Task { await self.bulkSet(selection, to: .visible) } }
        }
    }

    private var rows: [RepoRow] {
        var out: [RepoRow] = []
        for (index, name) in self.session.settings.repoList.pinnedRepositories.enumerated() {
            out.append(RepoRow(name: name, visibility: .pinned, sortKey: index))
        }
        for name in self.session.settings.repoList.hiddenRepositories where !out.contains(where: { $0.name == name }) {
            out.append(RepoRow(name: name, visibility: .hidden, sortKey: Int.max))
        }
        return out.sorted { lhs, rhs in
            if lhs.sortKey != rhs.sortKey { return lhs.sortKey < rhs.sortKey }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func addNewRepo(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self.newRepoInput = ""
        Task { await self.set(trimmed, to: self.newRepoVisibility) }
    }

    private func set(_ name: String, to visibility: RepoVisibility) async {
        await self.appState.setVisibility(for: name, to: visibility)
    }

    private func bulkSet(_ ids: Set<String>, to visibility: RepoVisibility) async {
        for id in ids {
            await self.set(id, to: visibility)
        }
        await MainActor.run { self.selection.removeAll() }
    }

    private func deleteSelection() {
        let ids = self.selection
        Task {
            await self.bulkSet(ids, to: .visible)
        }
    }
}

// MARK: - Autocomplete helper

private struct RepoRow: Identifiable, Hashable {
    var id: String { self.name }
    let name: String
    var visibility: RepoVisibility
    let sortKey: Int
}

private struct RepoInputRow<Accessory: View>: View {
    let placeholder: String
    let buttonTitle: String
    @Binding var text: String
    var onCommit: (String) -> Void
    @Bindable var session: Session
    let appState: AppState
    let includePublic: Bool
    var accessory: () -> Accessory
    @State private var suggestions: [Repository] = []
    @State private var isLoading = false
    @State private var showSuggestions = false
    @State private var selectedIndex = -1
    @State private var keyboardNavigating = false
    @State private var textFieldSize: CGSize = .zero
    @FocusState private var isFocused: Bool
    @State private var searchTask: Task<Void, Never>?
    /// The connected Azure DevOps organization's repos, asked for once while this field is
    /// on screen (nil until then) and kept in memory only.
    @State private var azureRepos: [Repository]?

    private var trimmedText: String {
        self.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                ZStack(alignment: .trailing) {
                    TextField("Repository", text: self.$text, prompt: Text(verbatim: self.placeholder))
                        .multilineTextAlignment(.leading)
                        .textFieldStyle(.roundedBorder)
                        .focused(self.$isFocused)
                        .onChange(of: self.text) { _, _ in
                            self.keyboardNavigating = false
                            self.scheduleSearch()
                        }
                        .onSubmit { self.commit() }
                        .onChange(of: self.includePublic) { _, _ in self.scheduleSearch(immediate: true) }
                        .onTapGesture {
                            self.showSuggestions = true
                            self.scheduleSearch(immediate: true)
                        }
                        .onMoveCommand(perform: self.handleMove)
                        .background(
                            GeometryReader { geometry in
                                Color.clear
                                    .onAppear { self.textFieldSize = geometry.size }
                                    .onChange(of: geometry.size) { _, newSize in
                                        self.textFieldSize = newSize
                                    }
                            })
                        .background(
                            RepoAutocompleteWindowView(
                                suggestions: self.suggestions,
                                selectedIndex: self.$selectedIndex,
                                keyboardNavigating: self.keyboardNavigating,
                                onSelect: { suggestion in
                                    self.commit(suggestion)
                                    DispatchQueue.main.async {
                                        self.isFocused = true
                                    }
                                },
                                width: self.textFieldSize.width,
                                isShowing: Binding(
                                    get: {
                                        self.showSuggestions && self.isFocused && !self.suggestions.isEmpty
                                    },
                                    set: { self.showSuggestions = $0 }
                                )
                            )
                        )

                    if self.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 8)
                    }
                }

                self.accessory()

                Button(self.buttonTitle) { self.commit() }
                    .disabled(self.trimmedText.isEmpty)
            }
        }
        .onChange(of: self.isFocused) { _, newValue in
            if newValue {
                self.scheduleSearch(immediate: true)
            } else {
                self.hideSuggestionsSoon()
            }
        }
        .onDisappear { self.searchTask?.cancel() }
    }

    private func commit(_ value: String? = nil) {
        // A picked suggestion is already a stored key. Typed text is resolved against what's
        // shown; text that names no repo (an Azure `a/b/c`, say) is left in the field, unsaved.
        let resolved = value ?? RepoAutocompleteScoring.resolveTyped(self.trimmedText, among: self.suggestions)
        guard let trimmed = resolved?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return }
        self.text = ""
        self.suggestions = []
        self.showSuggestions = false
        self.selectedIndex = -1
        self.onCommit(trimmed)
    }

    private func scheduleSearch(immediate: Bool = false) {
        self.searchTask?.cancel()
        let query = self.text
        self.searchTask = Task {
            // Debounce to avoid hammering GitHub as the user types.
            if !immediate { try? await Task.sleep(nanoseconds: 450_000_000) }
            await self.loadSuggestions(query: query)
        }
    }

    private func loadSuggestions(query: String) async {
        await MainActor.run {
            self.isLoading = true
            self.showSuggestions = self.isFocused
        }
        defer {
            Task { @MainActor in self.isLoading = false }
        }

        let includeForks = await MainActor.run { self.session.settings.repoList.showForks }
        let includeArchived = await MainActor.run { self.session.settings.repoList.showArchived }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let mine = await self.ownRepositories(includeForks: includeForks, includeArchived: includeArchived)
        var others: [Repository] = []
        if self.includePublic, trimmed.count >= 3 {
            // Public search is extra: if it fails, your own matches still show.
            others = (try? await self.appState.github.searchRepositories(matching: trimmed)) ?? []
        }
        let merged = RepoAutocompleteScoring.suggestions(
            mine: mine,
            public: RepositoryFilter.apply(others, includeForks: includeForks, includeArchived: includeArchived),
            query: trimmed,
            limit: AppLimits.Autocomplete.settingsSearchLimit
        )

        guard !Task.isCancelled else { return }
        await MainActor.run {
            // A slower, older search must not paint over what's typed now.
            guard query == self.text else { return }
            self.suggestions = merged
            if self.selectedIndex >= self.suggestions.count {
                self.selectedIndex = -1
            }
            // Keep suggestions visible while typing even if focus flickers.
            self.showSuggestions = !self.suggestions.isEmpty && (self.isFocused || !self.trimmedText.isEmpty)
        }
    }

    /// Yours on GitHub and in Azure DevOps, asked side by side. One provider failing leaves the
    /// other's. Azure is asked at most once while this field is on screen, failed or not
    /// (a refresh asks again); what it answered stays in memory for the next keystroke.
    private func ownRepositories(includeForks: Bool, includeArchived: Bool) async -> [Repository] {
        let github = self.appState.github
        let appState = self.appState
        let known = self.azureRepos
        let mine = await RepoListSources.gather(
            github: { RepositoryFilter.apply(try await github.prefetchedRepositories(), includeForks: includeForks, includeArchived: includeArchived) },
            azure: { if let known { return known }
                return await appState.azureRepositoriesForPicker() }
        )
        if known == nil { await MainActor.run { self.azureRepos = mine.filter(\.isAzure) } }
        return mine
    }

    private func hideSuggestionsSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.showSuggestions = false
            self.selectedIndex = -1
        }
    }

    private typealias ScoredSuggestion = RepoAutocompleteScoring.Scored

    private func handleMove(_ direction: MoveCommandDirection) {
        guard !self.suggestions.isEmpty else { return }
        switch direction {
        case .down:
            self.keyboardNavigating = true
            let next = self.selectedIndex + 1
            self.selectedIndex = min(next, self.suggestions.count - 1)
        case .up:
            self.keyboardNavigating = true
            let prev = self.selectedIndex - 1
            self.selectedIndex = max(prev, 0)
        default:
            break
        }
    }
}
