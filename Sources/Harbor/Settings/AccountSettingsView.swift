import HarborCore
import SwiftUI

struct AccountSettingsView: View {
    @Bindable var session: Session
    let appState: AppState

    // GitHub state
    @State private var githubClientID = ""
    @State private var githubClientSecret = ""
    @State private var githubEnterpriseHost = ""
    @State private var githubValidationError: String?

    // Azure DevOps state
    @State private var azurePAT = ""
    @State private var azureOrganization = ""
    @State private var azureValidationError: String?

    // GitLab state
    @State private var gitlabInstanceURL = "https://gitlab.com"
    @State private var gitlabClientID = ""
    @State private var gitlabClientSecret = ""
    @State private var gitlabValidationError: String?

    var body: some View {
        ZStack {
            LiquidGlassBackground()

            ScrollView {
                VStack(spacing: 24) {
                    // Harbor Logo Header
                    HarborLogoHeader()

                    // Provider Cards Container
                    VStack(spacing: 20) {
                        // GitHub Section
                        ProviderCard(
                            title: "GitHub",
                            subtitle: "GitHub.com or Enterprise",
                            icon: "chevron.left.forwardslash.chevron.right",
                            iconColor: .purple,
                            accentColor: .purple,
                            isConnected: session.isGitHubConnected,
                            username: session.githubUser?.username,
                            host: session.settings.githubHost.host ?? "github.com",
                            onConnect: { startGitHubLogin() },
                            onDisconnect: { disconnectGitHub() }
                        ) {
                            githubConnectionContent
                        }

                        // Azure DevOps Section
                        ProviderCard(
                            title: "Azure DevOps",
                            subtitle: "Microsoft Visual Studio",
                            icon: "building.2",
                            iconColor: .blue,
                            accentColor: .blue,
                            isConnected: session.isAzureConnected,
                            username: session.azureUser?.displayName,
                            host: azureOrganization.isEmpty ? "myorg.visualstudio.com" : azureOrganization,
                            onConnect: { connectAzureDevOps() },
                            onDisconnect: { disconnectAzureDevOps() }
                        ) {
                            azureConnectionContent
                        }

                        // GitLab Section
                        ProviderCard(
                            title: "GitLab",
                            subtitle: "Self-hosted or gitlab.com",
                            icon: "terminal",
                            iconColor: .orange,
                            accentColor: .orange,
                            isConnected: session.isGitLabConnected,
                            username: session.gitlabUser?.name,
                            host: gitlabInstanceURL,
                            onConnect: { startGitLabLogin() },
                            onDisconnect: { disconnectGitLab() }
                        ) {
                            gitlabConnectionContent
                        }
                    }
                }
                .padding(20)
            }
        }
        .onAppear {
            // Load saved Azure DevOps settings
            if let org = UserDefaults.standard.string(forKey: "azureOrganization") {
                azureOrganization = org
            }
        }
    }

    // MARK: - GitHub Connection Content

    @ViewBuilder
    private var githubConnectionContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if session.isGitHubConnected {
                ConnectedUserView(
                    username: session.githubUser?.username ?? "User",
                    host: session.settings.githubHost.host ?? "github.com"
                )
            } else {
                CustomLabeledField(
                    title: "Client ID",
                    value: $githubClientID,
                    placeholder: "GitHub OAuth Client ID"
                )
                .disabled(session.account == .loggingIn)

                SecureLabeledField(
                    title: "Client Secret",
                    value: $githubClientSecret,
                    placeholder: "GitHub OAuth Client Secret"
                )
                .disabled(session.account == .loggingIn)

                if !githubEnterpriseHost.isEmpty || session.settings.enterpriseHost != nil {
                    Divider()
                        .opacity(0.5)

                    CustomLabeledField(
                        title: "Enterprise URL",
                        value: $githubEnterpriseHost,
                        placeholder: "https://github.example.com"
                    )
                    .disabled(session.account == .loggingIn)
                }

                if let error = githubValidationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button(session.account == .loggingIn ? "Signing in..." : "Sign in with GitHub") {
                    startGitHubLogin()
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.account == .loggingIn || githubClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || githubClientSecret.isEmpty)
                .frame(maxWidth: .infinity, alignment: .trailing)

                Text("Use credentials from an OAuth application you control. Harbor stores them and the resulting tokens in the system Keychain.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Azure Connection Content

    @ViewBuilder
    private var azureConnectionContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if session.isAzureConnected {
                ConnectedUserView(
                    username: session.azureUser?.displayName ?? "Azure User",
                    host: azureOrganization.isEmpty ? "myorg.visualstudio.com" : azureOrganization
                )
            } else {
                CustomLabeledField(
                    title: "Organization",
                    value: $azureOrganization,
                    placeholder: "myorg"
                )
                .disabled(session.isAzureConnecting || session.isAzureConnected)

                SecureLabeledField(
                    title: "Personal Access Token",
                    value: $azurePAT,
                    placeholder: "Azure DevOps PAT"
                )
                .disabled(session.isAzureConnecting || session.isAzureConnected)

                if let error = azureValidationError {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                        Text("Troubleshooting tips:")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("• Ensure PAT has 'Code (read)' scope")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("• Verify organization name matches your Azure DevOps URL")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("• Check that your PAT hasn't expired")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if session.isAzureConnected {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Connected as \(session.azureUser?.displayName ?? "User")")
                            .font(.subheadline)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                } else {
                    Button(session.isAzureConnecting ? "Connecting..." : "Connect Azure DevOps") {
                        connectAzureDevOps()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.isAzureConnecting || azureOrganization.isEmpty || azurePAT.isEmpty)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

                CollapsibleHelpBox(
                    title: "How to create a Personal Access Token",
                    content: {
                        VStack(alignment: .leading, spacing: 12) {
                            StepRow(number: 1, text: "Go to Azure DevOps: https://dev.azure.com/{your-org}")
                            StepRow(number: 2, text: "Click your avatar → Personal access tokens")
                            StepRow(number: 3, text: "Click 'New Token'")
                            StepRow(number: 4, text: "Set name: 'Harbor App'")
                            StepRow(number: 5, text: "Expiration: Choose a duration")
                            StepRow(number: 6, text: "Scopes: Select 'Code' → 'Read'")
                            StepRow(number: 7, text: "Copy the generated token and paste above")
                            LinkRow(icon: "safari", text: "Azure DevOps Docs", url: "https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/use-personal-access-tokens")
                        }
                    }
                )
            }
        }
    }

    // MARK: - GitLab Connection Content

    @ViewBuilder
    private var gitlabConnectionContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if session.isGitLabConnected {
                ConnectedUserView(
                    username: "GitLab User",
                    host: gitlabInstanceURL
                )
            } else {
                CustomLabeledField(
                    title: "GitLab Instance",
                    value: $gitlabInstanceURL,
                    placeholder: "https://gitlab.com"
                )
                .disabled(session.isGitLabConnecting)

                CustomLabeledField(
                    title: "Application ID",
                    value: $gitlabClientID,
                    placeholder: "GitLab Application ID"
                )
                .disabled(session.isGitLabConnecting)

                SecureLabeledField(
                    title: "Secret",
                    value: $gitlabClientSecret,
                    placeholder: "GitLab Application Secret"
                )
                .disabled(session.isGitLabConnecting)

                if let error = gitlabValidationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button(session.isGitLabConnecting ? "Connecting..." : "Sign in with GitLab") {
                    startGitLabLogin()
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.isGitLabConnecting)
                .frame(maxWidth: .infinity, alignment: .trailing)

                Text("Register an OAuth application in GitLab: Settings → Applications.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - GitHub Actions

    private func startGitHubLogin() {
        Task { @MainActor in
            session.account = .loggingIn
            githubValidationError = nil

            let enterpriseURL = normalizeEnterpriseHost(githubEnterpriseHost)

            let effectiveClientID = githubClientID.trimmingCharacters(in: .whitespacesAndNewlines)
            let effectiveClientSecret = githubClientSecret

            do {
                try await appState.auth.login(
                    clientID: effectiveClientID,
                    clientSecret: effectiveClientSecret,
                    host: enterpriseURL ?? session.settings.githubHost,
                    loopbackPort: session.settings.loopbackPort
                )
                if let user = try? await appState.github.currentUser() {
                    session.account = .loggedIn(user)
                    session.lastError = nil
                }
            } catch {
                session.account = .loggedOut
                githubValidationError = error.localizedDescription
            }
        }
    }

    private func disconnectGitHub() {
        Task {
            await appState.auth.logout()
            session.account = .loggedOut
        }
    }

    private func normalizeEnterpriseHost(_ host: String) -> URL? {
        guard !host.isEmpty else { return nil }
        guard var components = URLComponents(string: host) else { return nil }
        if components.scheme == nil { components.scheme = "https" }
        guard components.scheme?.lowercased() == "https", components.host != nil else { return nil }
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
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
                azureValidationError = "Connection failed: \(error.localizedDescription)"
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

// MARK: - Provider Card

struct ProviderCard<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let iconColor: Color
    let accentColor: Color
    let isConnected: Bool
    let username: String?
    let host: String
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                // Header with colored accent
                HStack(spacing: 12) {
                    // Colored accent bar
                    RoundedRectangle(cornerRadius: 2)
                        .fill(accentColor)
                        .frame(width: 4)

                    // Icon
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(iconColor)
                        .frame(width: 32)

                    // Title and subtitle
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Connection status
                    if isConnected {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(.green)
                                .frame(width: 8, height: 8)
                            Text("Connected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Button("Disconnect", action: onDisconnect)
                            .font(.caption)
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                    }
                }

                Divider()
                    .opacity(0.5)

                // Content
                content()
            }
            .padding(16)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(accentColor.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Connected User View

struct ConnectedUserView: View {
    let username: String
    let host: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text(username)
                    .font(.headline)
                Text(host)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.green.opacity(0.1))
        )
    }
}

// MARK: - Labeled Fields

struct CustomLabeledField: View {
    let title: String
    @Binding var value: String
    var placeholder: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $value)
                .textFieldStyle(.roundedBorder)
        }
    }
}

struct SecureLabeledField: View {
    let title: String
    @Binding var value: String
    var placeholder: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            SecureField(placeholder, text: $value)
                .textFieldStyle(.roundedBorder)
        }
    }
}

// MARK: - Help Components

struct CollapsibleHelpBox<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
                    .padding(.leading, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.top, 8)
    }
}

struct StepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number)")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.blue))
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct LinkRow: View {
    let icon: String
    let text: String
    let url: String

    var body: some View {
        Button {
            if let linkUrl = URL(string: url) {
                NSWorkspace.shared.open(linkUrl)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(text)
                    .font(.caption2)
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .font(.caption2)
            }
            .foregroundStyle(.blue)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AccountSettingsView(
        session: Session(),
        appState: AppState(platform: ApplePlatformServices())
    )
    .frame(width: 520, height: 700)
}

// MARK: - Harbor Logo Header

struct HarborLogoHeader: View {
    var body: some View {
        VStack(spacing: 12) {
            HarborIconView(size: 64)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)

            Text("Harbor")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Connect your repositories")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 20)
    }
}
