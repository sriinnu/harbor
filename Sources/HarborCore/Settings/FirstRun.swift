import Foundation

/// When the panel shows its welcome. Pure, so the rule is tested without a panel.
public enum FirstRun {
    /// The welcome shows only for an app that was never set up: no account, no project folders,
    /// and the user has not dismissed it. Either setup step, or "Not now", ends it for good.
    public static func isVisible(dismissed: Bool, signedIn: Bool, hasProjectFolders: Bool) -> Bool {
        !dismissed && !signedIn && !hasProjectFolders
    }
}
