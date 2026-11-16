import AppKit
import HarborCore
import SwiftUI

struct AccountSettingsView: View {
    @Bindable var session: Session
    let appState: AppState

    // GitHub state
    @State private var githubClientID = HarborAuthDefaults.clientID
    @State private var githubClientSecret = ""
    @State private var githubEnterpriseHost = ""
    @State private var githubValidationError: String?
    @State private var githubShowsOwnApp = false
    @State private var githubShowsTokenEntry = false
    @State private var githubToken = ""
    @State private var githubTokenError: String?
    @State private var githubTokenChecking = false
    @State private var githubShowsAddAccount = false
    @State private var githubAddError: String?
    @State private var accountPendingRemoval: GitHubAccount?

    // Azure DevOps state
    @State private var azurePAT = ""
    @State private var azureOrganization = ""
    @State private var azureValidationError: String?
    @State private var azureShowsHelp = false

    // GitLab state
    @State private var gitlabInstanceURL = "https://gitlab.com"
    @State private var gitlabClientID = ""
    @State private var gitlabClientSecret = ""
    @State private var gitlabValidationError: String?

    var body: some View {
        SettingsPane {
            self.githubSection
            self.azureSection
            self.gitlabSection
            self.securitySection
        }
        .onAppear {
            // Accounts added with `harborcli login` appear without a relaunch; the account on screen stays.
            appState.reconcileAccountIndex(adoptActive: false)
            // Load saved Azure DevOps settings
            if let org = UserDefaults.standard.string(forKey: "azureOrganization") {
                azureOrganization = org
            }
            // Someone already on an enterprise host or their own app sees those fields open.
            if session.settings.enterpriseHost != nil || githubClientID != HarborAuthDefaults.clientID {
                githubShowsOwnApp = true
            }
        }
    }

    // MARK: - GitHub

    @ViewBuilder
    private var githubSection: some View {
        Section {
            if session.isGitHubConnected {
                if appState.githubAccounts.isEmpty {
                    // Signed in, the account's own Keychain item not written yet (the first refresh does it).
                    ConnectedAccountRow(
                        name: session.githubUser?.username ?? "User",
                        host: (session.settings.githubHost.host ?? "github.com")
                            + (appState.auth.authKind == .personalAccessToken ? " · personal access token" : ""),
                        disconnect: disconnectGitHub
                    )
                } else {
                    ForEach(appState.githubAccounts) { account in
                        self.accountRow(account)
                    }
                }
                self.addAccountGroup
            } else {
                LabeledContent {
                    Button(session.account.isLoggingIn ? "Signing In…" : "Sign In…") {
                        startGitHubLogin()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.account.isLoggingIn)
                } label: {
                    Text("Not connected")
                    Text("Sign in with a one-time code on github.com.")
                }

                if let prompt = session.account.deviceCodePrompt {
                    DeviceCodePromptView(prompt: prompt) {
                        appState.cancelGitHubSignIn()
                    }
                }

                if let error = githubValidationError {
                    SettingsErrorText(text: error)
                }

                DisclosureGroup("Use a token instead", isExpanded: $githubShowsTokenEntry) {
                    self.githubTokenEntry
                }
                .disabled(session.account.isLoggingIn)

                DisclosureGroup("GitHub Enterprise or your own OAuth app", isExpanded: $githubShowsOwnApp) {
                    TextField("Enterprise host", text: $githubEnterpriseHost, prompt: Text(verbatim: "ghe.example.com"))
                    TextField("Client ID", text: $githubClientID, prompt: Text("OAuth app client ID"))
                    SecureField("Client secret", text: $githubClientSecret, prompt: Text("Only for your own OAuth app"))
                }
                .disabled(session.account.isLoggingIn)
            }
        } header: {
            Text("GitHub")
        } footer: {
            if !session.isGitHubConnected {
                SettingsFooter("Leave the secret empty to use the one-time code. For GitHub Enterprise, add your own OAuth app's ID and secret.")
            }
        }
    }

    private func accountRow(_ account: GitHubAccount) -> some View {
        let isActive = account.id == appState.activeGitHubAccountID
        return LabeledContent {
            HStack(spacing: 12) {
                if isActive {
                    SettingsStatus(text: "Active", kind: .ok)
                } else {
                    Button("Switch") { switchGitHubAccount(account) }
                        .disabled(session.account.isLoggingIn || session.isAddingAccount)
                }
                Button("Remove", role: .destructive) { accountPendingRemoval = account }
            }
        } label: {
            Text(verbatim: account.login)
            Text(verbatim: account.host + (account.kind == .personalAccessToken ? " · personal access token" : ""))
        }
        .confirmationDialog(
            "Remove \(accountPendingRemoval?.login ?? "this account") from Harbor?",
            isPresented: Binding(
                get: { accountPendingRemoval?.id == account.id },
                set: { if !$0 { accountPendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                accountPendingRemoval = nil
                Task { await appState.removeGitHubAccount(account.id) }
            }
        } message: {
            Text("Its token is deleted from the Keychain. Your repositories on GitHub are not touched.")
        }
    }

    @ViewBuilder
    private var addAccountGroup: some View {
        DisclosureGroup("Add another account", isExpanded: $githubShowsAddAccount) {
            VStack(alignment: .leading, spacing: 10) {
                SettingsActionRow {
                    Button(session.isAddingAccount ? "Waiting for GitHub…" : "Sign in with a code") {
                        addGitHubAccountWithCode()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.isAddingAccount || githubTokenChecking)
                }
                if let prompt = session.addAccountPrompt {
                    DeviceCodePromptView(prompt: prompt) {
                        appState.cancelGitHubSignIn()
                    }
                }
                if let error = githubAddError {
                    SettingsErrorText(text: error)
                }
                Text("Or use a token:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                self.githubTokenEntry
            }
            .padding(.vertical, 4)
        }
        .disabled(session.account.isLoggingIn)
    }

    private var githubTokenEntry: some View {
        VStack(alignment: .leading, spacing: 8) {
            SecureField("Personal access token", text: $githubToken, prompt: Text(verbatim: "ghp_… or github_pat_…"))
                .disabled(githubTokenChecking)
            Text("Classic token with the repo and read:org scopes. Or a fine-grained token with read access to Metadata and Contents and read and write on Pull requests, Checks and Actions for the repos you want shown. github.com only.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SettingsLink(title: "Create a token on GitHub", url: GitHubTokenValidator.tokensPage.absoluteString)
            if let error = githubTokenError {
                SettingsErrorText(text: error)
            }
            SettingsActionRow {
                Button(githubTokenChecking ? "Checking…" : "Validate & Save") {
                    saveGitHubToken()
                }
                .buttonStyle(.borderedProminent)
                .disabled(githubTokenChecking || githubToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Azure DevOps

    @ViewBuilder
    private var azureSection: some View {
        Section {
            if session.isAzureConnected {
                ConnectedAccountRow(
                    name: session.azureUser?.displayName ?? "Azure User",
                    host: azureOrganization.isEmpty ? "myorg.visualstudio.com" : azureOrganization,
                    disconnect: disconnectAzureDevOps
                )
            } else {
                TextField("Organization", text: $azureOrganization, prompt: Text(verbatim: "myorg"))
                    .disabled(session.isAzureConnecting || session.isAzureConnected)
                SecureField("Personal access token", text: $azurePAT, prompt: Text("Needs Code (Read)"))
                    .disabled(session.isAzureConnecting || session.isAzureConnected)

                if let error = azureValidationError {
                    VStack(alignment: .leading, spacing: 6) {
                        SettingsErrorText(text: error)
                        Text(verbatim: "Check that the token has the Code (Read) scope and hasn't expired, and that the organization matches your Azure DevOps URL.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                SettingsActionRow {
                    Button(session.isAzureConnecting ? "Connecting…" : "Connect") {
                        connectAzureDevOps()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.isAzureConnecting || azureOrganization.isEmpty || azurePAT.isEmpty)
                }

                DisclosureGroup("How to create a personal access token", isExpanded: $azureShowsHelp) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(Self.azureSteps.enumerated()), id: \.offset) { index, step in
                            Text(verbatim: "\(index + 1). \(step)")
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        SettingsLink(title: "Open the token page", url: self.azureTokenPageURL.absoluteString)
                            .padding(.top, 2)
                        SettingsLink(
                            title: "Azure DevOps documentation",
                            url: "https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/use-personal-access-tokens"
                        )
                        .padding(.top, 2)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
                // Opening the help also opens Azure's token page, so the steps sit beside it.
                .onChange(of: azureShowsHelp) { _, expanded in
                    if expanded { NSWorkspace.shared.open(self.azureTokenPageURL) }
                }
            }
        } header: {
            Text("Azure DevOps")
        }
    }

    /// The organization's token page when an organization is typed, else Azure DevOps' home,
    /// which lands on the org picker. Accepts "myorg" or a pasted dev.azure.com / visualstudio.com URL.
    private var azureTokenPageURL: URL {
        Self.azureTokenPage(organization: azureOrganization)
    }

    static func azureTokenPage(organization: String) -> URL {
        var org = organization.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://", "dev.azure.com/"] where org.lowercased().hasPrefix(prefix) {
            org = String(org.dropFirst(prefix.count))
        }
        if let range = org.range(of: ".visualstudio.com", options: .caseInsensitive) {
            org = String(org[..<range.lowerBound])
        }
        org = org.split(separator: "/").first.map(String.init) ?? ""
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard !org.isEmpty, org.unicodeScalars.allSatisfy(allowed.contains),
              let url = URL(string: "https://dev.azure.com/\(org)/_usersSettings/tokens")
        else { return URL(string: "https://dev.azure.com/")! }
        return url
    }

    private static let azureSteps = [
        "Open dev.azure.com/{your-org}.",
        "Choose your avatar, then Personal access tokens.",
        "Choose New Token and name it \"Harbor\".",
        "Pick an expiration.",
        "Under Scopes, select Code → Read.",
        "Create it, copy the token and paste it above."
    ]

    // MARK: - GitLab

    @ViewBuilder
    private var gitlabSection: some View {
        Section {
            if session.isGitLabConnected {
                ConnectedAccountRow(
                    name: "GitLab User",
                    host: gitlabInstanceURL,
                    disconnect: disconnectGitLab
                )
            } else {
                TextField("Instance", text: $gitlabInstanceURL, prompt: Text(verbatim: "https://gitlab.com"))
                    .disabled(session.isGitLabConnecting)
                TextField("Application ID", text: $gitlabClientID, prompt: Text("From your GitLab application"))
                    .disabled(session.isGitLabConnecting)
                SecureField("Secret", text: $gitlabClientSecret, prompt: Text("Application secret"))
                    .disabled(session.isGitLabConnecting)

                if let error = gitlabValidationError {
                    SettingsErrorText(text: error)
                }

                SettingsActionRow {
                    Button(session.isGitLabConnecting ? "Connecting…" : "Sign In…") {
                        startGitLabLogin()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.isGitLabConnecting)
                }
            }
        } header: {
            Text("GitLab")
        } footer: {
            if !session.isGitLabConnected {
                SettingsFooter("Register an OAuth application in GitLab under Settings → Applications.")
            }
        }
    }

    // MARK: - Security

    private var securitySection: some View {
        Section {
            LabeledContent("Token storage") {
                self.tokenStorageStatus
            }
        } header: {
            Text("Security")
        } footer: {
            SettingsFooter("Tokens live in your macOS Keychain, never in files or settings.")
        }
    }

    private var tokenStorageStatus: SettingsStatus {
        do {
            let count = appState.platform.tokenStorage.accountKeys().count
            let hasTokens = try appState.platform.tokenStorage.load() != nil
            let text = count > 1 ? "Keychain · \(count) accounts stored" : (hasTokens ? "Keychain · tokens stored" : "Keychain · no tokens")
            return SettingsStatus(text: text, kind: hasTokens ? .ok : .neutral)
        } catch {
            return SettingsStatus(text: "Error: \(error.reportableMessage ?? "interrupted, try again")", kind: .warning)
        }
    }

    // MARK: - GitHub Actions

    private func startGitHubLogin() {
        Task { @MainActor in
            githubValidationError = nil
            // An unusable enterprise host must say so, not quietly sign in to github.com.
            var enterpriseHost: URL?
            if !githubEnterpriseHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                guard let host = try? OAuthLoginFlow.normalizeHost(githubEnterpriseHost) else {
                    githubValidationError = "Enterprise host must be an https address, like ghe.example.com."
                    return
                }
                enterpriseHost = host
            }
            githubValidationError = await appState.signInToGitHub(
                clientID: githubClientID,
                clientSecret: githubClientSecret,
                enterpriseHost: enterpriseHost
            )
        }
    }

    private func addGitHubAccountWithCode() {
        Task { @MainActor in
            githubAddError = nil
            githubAddError = await appState.signInToGitHub(addingAccount: true)
        }
    }

    private func switchGitHubAccount(_ account: GitHubAccount) {
        Task { @MainActor in
            githubAddError = await appState.switchGitHubAccount(to: account.id)
        }
    }

    private func saveGitHubToken() {
        Task { @MainActor in
            githubTokenChecking = true
            githubTokenError = nil
            githubTokenError = await appState.signInWithToken(githubToken)
            // An accepted token leaves the field; a refused one stays so a typo can be fixed in place.
            if githubTokenError == nil { githubToken = "" }
            githubTokenChecking = false
        }
    }

    private func disconnectGitHub() {
        githubToken = ""
        Task { await appState.signOut() }
    }

    // MARK: - Azure DevOps Actions

    private func connectAzureDevOps() {
        Task { @MainActor in
            session.isAzureConnecting = true
            azureValidationError = nil

            UserDefaults.standard.set(azureOrganization, forKey: "azureOrganization")

            do {
                let result = try await appState.azureAuth.connect(
                    pat: azurePAT,
                    organization: azureOrganization
                )
                session.isAzureConnected = true
                session.azureUser = result.user
                session.lastError = nil
                azurePAT = ""
            } catch let error as AzureDevOpsAuthError {
                azureValidationError = error.localizedDescription
                session.isAzureConnected = false
                session.azureUser = nil
            } catch {
                azureValidationError = error.reportableMessage.map { "Connection failed: \($0)" }
                session.isAzureConnected = false
                session.azureUser = nil
            }

            session.isAzureConnecting = false
        }
    }

    private func disconnectAzureDevOps() {
        Task {
            await appState.azureAuth.disconnect()
        }
        UserDefaults.standard.removeObject(forKey: "azureOrganization")
        azurePAT = ""
        azureOrganization = ""
        session.isAzureConnected = false
        session.azureUser = nil
    }

    // MARK: - GitLab Actions

    private func startGitLabLogin() {
        Task { @MainActor in
            session.isGitLabConnecting = true
            gitlabValidationError = nil

            gitlabValidationError = "GitLab integration coming soon"
            session.isGitLabConnecting = false
        }
    }

    private func disconnectGitLab() {
        gitlabClientID = ""
        gitlabClientSecret = ""
        session.isGitLabConnected = false
    }
}

// MARK: - Rows

/// A signed-in account: who and where on the leading side, state and Disconnect trailing.
private struct ConnectedAccountRow: View {
    let name: String
    let host: String
    let disconnect: () -> Void

    var body: some View {
        LabeledContent {
            HStack(spacing: 12) {
                SettingsStatus(text: "Connected", kind: .ok)
                Button("Disconnect", action: self.disconnect)
            }
        } label: {
            Text(verbatim: self.name)
            Text(verbatim: self.host)
        }
    }
}

/// Shows the device-flow code while Harbor waits for the user to approve on GitHub.
private struct DeviceCodePromptView: View {
    let prompt: DeviceAuthorization
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enter this code on GitHub")
                .font(.headline)
            Text(prompt.userCode)
                .font(.system(.title2, design: .monospaced).weight(.semibold))
                .textSelection(.enabled)
                .accessibilityLabel("Code \(prompt.userCode.map(String.init).joined(separator: " "))")
            Text("Copied to your clipboard. Paste it at \(prompt.verificationURL.host ?? "github.com")\(prompt.verificationURL.path).")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Open GitHub") { NSWorkspace.shared.open(prompt.verificationURL) }
                    .buttonStyle(.borderedProminent)
                Button("Copy Code") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(prompt.userCode, forType: .string)
                }
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    AccountSettingsView(
        session: Session(),
        appState: AppState(platform: ApplePlatformServices())
    )
    .frame(width: 560, height: 620)
}
