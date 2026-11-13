import Foundation

enum SecurityScopedBookmark {
    static func create(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    static func resolve(_ data: Data) -> URL? {
        var isStale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    /// Runs `perform` with access to the first bookmarked root that contains `url`.
    static func withAccess(to url: URL, rootBookmarks: [Data], perform: () -> Void) {
        guard url.isFileURL else {
            perform()
            return
        }
        let targetURL = (url as NSURL).filePathURL ?? url
        let targetPath = targetURL.standardizedFileURL.path
        for data in rootBookmarks {
            guard let scopedRoot = resolve(data) else { continue }
            let rootURL = (scopedRoot as NSURL).filePathURL ?? scopedRoot
            let rootPath = rootURL.standardizedFileURL.path
            guard targetPath == rootPath || targetPath.hasPrefix(rootPath + "/") else { continue }
            let didStart = scopedRoot.startAccessingSecurityScopedResource()
            defer {
                if didStart {
                    scopedRoot.stopAccessingSecurityScopedResource()
                }
            }
            perform()
            return
        }
        perform()
    }
}
