import SwiftUI

/// What the panel shows an app that was never set up: one line on what Harbor is, the two ways
/// to start, and an honest note on Tower. It goes away once either step is done, or for good
/// on "Not now" (see `FirstRun`).
struct PanelWelcomeView: View {
    let actions: HarborPanelActions
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Welcome to Harbor")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(self.skin.text)
                .accessibilityAddTraits(.isHeader)
            Text("Your repositories, builds and reviews, in one panel in the menu bar.")
                .font(.system(size: 12))
                .foregroundStyle(self.skin.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button("Sign in with GitHub", action: self.actions.signIn)
                .buttonStyle(PanelPrimaryButtonStyle())
                .accessibilityHint("Opens GitHub in your browser to approve Harbor. No password is typed here")
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                PanelTextButton(title: "Add a projects folder…", symbol: "folder.badge.plus", action: self.actions.addProjectFolder)
                    .accessibilityHint("Choose the folder where your Git clones live. Harbor reads it on this Mac only")
                Text("Local clones show their branch and whether they are behind, with no account needed.")
                    .font(.system(size: self.skin.row.detailSize + 1))
                    .foregroundStyle(self.skin.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Tower · optional")
                    .font(.system(size: self.skin.row.detailSize + 1, weight: .semibold))
                    .foregroundStyle(self.skin.text)
                Text("Once a projects folder is added, Tower also watches the worktrees your coding agents create there. There is nothing else to turn on.")
                    .font(.system(size: self.skin.row.detailSize + 1))
                    .foregroundStyle(self.skin.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            PanelTextButton(title: "Not now", action: self.actions.dismissWelcome)
                .accessibilityHint("Hides this welcome for good. Sign in and folders stay in Settings")
        }
        .padding(12)
    }
}
