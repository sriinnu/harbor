import AppKit
import HarborCore

/// The panel's "Add a projects folder…": the same folder picker and bookkeeping as Settings ›
/// Local Git, for the first-run welcome. The folder is kept as a security-scoped bookmark.
@MainActor
enum ProjectFolderPicker {
    /// Asks for one or more folders and adds them; returns whether any was added.
    @discardableResult
    static func addFolders(appState: AppState) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Projects", isDirectory: true)
        NSApp.activate()
        guard panel.runModal() == .OK else { return false }
        var added = false
        for url in panel.urls {
            let filePathURL = (url as NSURL).filePathURL ?? url
            let resolvedPath = filePathURL.resolvingSymlinksInPath().path
            let didAdd = appState.session.settings.localProjects.addRoot(
                PathFormatter.abbreviateHome(resolvedPath),
                bookmark: SecurityScopedBookmark.create(for: url)
            )
            added = added || didAdd
        }
        guard added else { return false }
        appState.persistSettings()
        appState.refreshLocalProjects(forceRescan: true)
        appState.requestRefresh(cancelInFlight: true)
        return true
    }
}
