import HarborCore
import SwiftUI

struct DebugSettingsView: View {
    @Bindable var session: Session
    let appState: AppState
    @State private var diagnostics = DiagnosticsSummary.empty
    // Filled in by .task: probing git runs a process, which must not happen while SwiftUI
    // builds the view (it spins the run loop mid-update and trips an AttributeGraph abort).
    @State private var gitExecutableInfo = GitExecutableInfo(path: "Checking…", version: nil, error: nil, isSandboxed: false)

    var body: some View {
        SettingsPane {
            Section {
                LabeledContent("Caches") {
                    HStack(spacing: 8) {
                        Button("Clear All") {
                            Task {
                                await self.appState.clearCaches()
                                await self.loadDiagnosticsIfEnabled()
                            }
                        }
                        Button("Heatmap") {
                            self.appState.clearContributionCache()
                        }
                        .help("Clear the contribution heatmap cache")
                        Button("Releases") {
                            Task {
                                await self.appState.github.clearCache()
                                self.appState.requestRefresh(cancelInFlight: true)
                            }
                        }
                        .help("Clear the release cache and refresh")
                    }
                }
                LabeledContent("Data") {
                    Button("Force Refresh") {
                        self.appState.requestRefresh(cancelInFlight: true)
                    }
                }
            } header: {
                Text("Actions")
            }

            Section {
                LabeledContent("Git binary") {
                    Text(self.gitExecutableInfo.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                LabeledContent("Git version") {
                    Text(self.gitExecutableInfo.version ?? "—")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                LabeledContent("Git sandboxed") {
                    Text(self.gitExecutableInfo.isSandboxed ? "Yes" : "No")
                }
                if let error = self.gitExecutableInfo.error, !error.isEmpty {
                    LabeledContent("Git error") {
                        Text(error)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("API host") {
                    Text(self.diagnostics.apiHost.absoluteString)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                LabeledContent("REST rate limit") {
                    Text(
                        self.diagnostics.restRateLimit.map(self.formatRate)
                            ?? "— (not fetched yet)"
                    )
                }
                LabeledContent("GraphQL rate limit") {
                    Text(
                        self.diagnostics.graphQLRateLimit.map(self.formatRate)
                            ?? "— (not fetched yet)"
                    )
                }
                if let reset = diagnostics.rateLimitReset {
                    LabeledContent("Rate limit resets") {
                        Text(RelativeFormatter.string(from: reset, relativeTo: Date()))
                    }
                }
                if let error = diagnostics.lastRateLimitError {
                    LabeledContent("Last API notice") { Text(error).foregroundStyle(.red) }
                }
                LabeledContent("Backoff entries") { Text("\(self.diagnostics.backoffEntries)") }
                LabeledContent("ETag entries") { Text("\(self.diagnostics.etagEntries)") }
                SettingsActionRow {
                    Button("Reload") { Task { await self.loadDiagnosticsIfEnabled() } }
                }
            } header: {
                Text("Diagnostics")
            } footer: {
                if !self.session.settings.diagnosticsEnabled {
                    SettingsFooter("Turn on Diagnostic logging in General to collect these.")
                }
            }
            .disabled(!self.session.settings.diagnosticsEnabled)
        }
        .onChange(of: self.session.settings.diagnosticsEnabled) { _, _ in
            Task { await self.loadDiagnosticsIfEnabled() }
        }
        .task {
            self.gitExecutableInfo = await Task.detached { LocalProjectsService.gitExecutableInfo() }.value
            await self.loadDiagnosticsIfEnabled()
        }
    }

    private func loadDiagnosticsIfEnabled() async {
        guard self.session.settings.diagnosticsEnabled else {
            self.diagnostics = .empty
            return
        }
        self.diagnostics = await self.appState.diagnostics()
    }

    private func formatRate(_ snapshot: RateLimitSnapshot) -> String {
        var parts: [String] = []
        if let resource = snapshot.resource?.uppercased() {
            parts.append(resource)
        }
        if let remaining = snapshot.remaining, let limit = snapshot.limit {
            parts.append("\(remaining)/\(limit) left")
        } else if let remaining = snapshot.remaining {
            parts.append("\(remaining) remaining")
        } else if let limit = snapshot.limit {
            parts.append("limit \(limit)")
        }
        if let used = snapshot.used {
            parts.append("\(used) used")
        }
        if let reset = snapshot.reset {
            parts.append("resets \(RelativeFormatter.string(from: reset, relativeTo: Date()))")
        }
        let text = parts.joined(separator: " • ")
        return text.isEmpty ? "—" : text
    }
}
