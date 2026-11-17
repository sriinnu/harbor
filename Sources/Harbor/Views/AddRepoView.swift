import HarborCore
import SwiftUI

struct AddRepoView: View {
    @Binding var isPresented: Bool
    @Bindable var session: Session
    let appState: AppState
    var onSelect: (Repository) -> Void
    @State private var query = ""
    @State private var results: [Repository] = []
    @State private var isLoading = false
    /// Off: only your repos (yours, your orgs', collaborations).
    @State private var includePublic = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pin a repository")
                .font(.headline)
            TextField("owner/name", text: self.$query)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    Task { await self.search() }
                }
            Toggle("Include public repos", isOn: self.$includePublic)
                .toggleStyle(.checkbox)
                .onChange(of: self.includePublic) { _, _ in Task { await self.search() } }
            if self.isLoading {
                ProgressView().padding(.vertical, 8)
            }
            List(self.results) { repo in
                Button {
                    self.onSelect(repo)
                    self.isPresented = false
                } label: {
                    VStack(alignment: .leading) {
                        Text(repo.displayName).bold()
                        if let azure = repo.azure {
                            Text(azure.isDisabled ? "Azure DevOps · \(azure.organization) · disabled" : "Azure DevOps · \(azure.organization)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let release = repo.latestRelease {
                            Text("Latest: \(release.name)").font(.caption)
                        } else {
                            Text("Issues: \(repo.stats.openIssues) • Owner: \(repo.owner)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(repo.isPickerDisabled)
            }
            HStack {
                Spacer()
                Button("Cancel") { self.isPresented = false }
            }
        }
        .padding(16)
        .frame(width: 380, height: 420)
        .onAppear { Task { await self.searchDefault() } }
    }

    private func searchDefault() async { await self.search() }

    private func search() async {
        self.isLoading = true
        defer { self.isLoading = false }
        do {
            let includeForks = await MainActor.run { self.session.settings.repoList.showForks }
            let includeArchived = await MainActor.run { self.session.settings.repoList.showArchived }
            let trimmed = self.query.trimmingCharacters(in: .whitespacesAndNewlines)
            let filtered: [Repository]
            if trimmed.isEmpty {
                let recent = try await self.appState.github.recentRepositories(limit: AppLimits.Autocomplete.addRepoRecentLimit)
                filtered = RepositoryFilter.apply(recent, includeForks: includeForks, includeArchived: includeArchived)
            } else {
                // Yours on GitHub and in Azure DevOps; one failing leaves the other's.
                let github = self.appState.github
                let appState = self.appState
                let mine = await RepoListSources.gather(
                    github: { RepositoryFilter.apply(try await github.prefetchedRepositories(), includeForks: includeForks, includeArchived: includeArchived) },
                    azure: { await appState.azureRepositoriesForPicker() }
                )
                var others: [Repository] = []
                if self.includePublic {
                    // Public search is extra: if it fails, your own matches still show.
                    others = (try? await self.appState.github.searchRepositories(matching: trimmed)) ?? []
                }
                filtered = RepoAutocompleteScoring.suggestions(
                    mine: mine,
                    public: RepositoryFilter.apply(others, includeForks: includeForks, includeArchived: includeArchived),
                    query: trimmed,
                    limit: AppLimits.Autocomplete.addRepoRecentLimit
                )
            }
            await MainActor.run { self.results = filtered }
        } catch {
            // Ignored; UI stays empty
        }
    }
}
