import Foundation
@testable import HarborCore
import Testing

struct LocalProjectsRootsTests {
    private func decode(_ json: String) throws -> LocalProjectsSettings {
        try JSONDecoder().decode(LocalProjectsSettings.self, from: Data(json.utf8))
    }

    @Test
    func decode_legacyRootPath_becomesOneElementList() throws {
        let settings = try self.decode(#"{"rootPath":"~/Code","rootBookmarkData":"AQIDBA=="}"#)
        #expect(settings.rootPaths == ["~/Code"])
        #expect(settings.rootBookmarks == ["~/Code": Data([1, 2, 3, 4])])
    }

    @Test
    func decode_missingBothKeys_isEmptyLikeAFreshInstall() throws {
        let settings = try self.decode(#"{"autoSyncEnabled":false}"#)
        #expect(settings.rootPaths == [])
        #expect(settings.autoSyncEnabled == false)
    }

    @Test
    func decode_legacyTildeCode_isKept() throws {
        #expect(try self.decode(#"{"rootPath":"~/Code"}"#).rootPaths == ["~/Code"])
    }

    @Test
    func decode_newKey_isKeptInOrder() throws {
        let settings = try self.decode(#"{"rootPaths":["~/b","~/a"],"rootPath":"~/old"}"#)
        #expect(settings.rootPaths == ["~/b", "~/a"])
    }

    @Test
    func decode_emptyList_staysEmpty() throws {
        let settings = try self.decode(#"{"rootPaths":[]}"#)
        #expect(settings.rootPaths == [])
    }

    @Test
    func encode_writesNewKeyOnly() throws {
        var settings = LocalProjectsSettings()
        settings.rootPaths = ["~/a", "~/b"]
        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any]
        )
        #expect(object["rootPaths"] as? [String] == ["~/a", "~/b"])
        #expect(object["rootPath"] == nil)
        #expect(object["rootBookmarkData"] == nil)
    }

    @Test
    func addRoot_rejectsDuplicatesByRealPath_andRemoveDropsBookmark() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harbor-roots-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let link = dir.deletingLastPathComponent().appendingPathComponent("harbor-link-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: dir)
        defer { try? FileManager.default.removeItem(at: link) }

        var settings = LocalProjectsSettings()
        settings.rootPaths = []
        #expect(settings.addRoot(dir.path, bookmark: Data([9])) == true)
        #expect(settings.addRoot(link.path) == false)
        #expect(settings.rootPaths == [dir.path])
        settings.removeRoot(dir.path)
        #expect(settings.rootPaths == [])
        #expect(settings.rootBookmarks == [:])
    }

    @Test
    func discover_multipleRoots_dedupesOverlap_andSkipsMissing() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harbor-multiroot-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("one", isDirectory: true)
        let second = root.appendingPathComponent("two", isDirectory: true)
        for repo in [first.appendingPathComponent("alpha"), second.appendingPathComponent("beta")] {
            try FileManager.default.createDirectory(
                at: repo.appendingPathComponent(".git", isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        let found = LocalProjectsService().discoverRepoRoots(
            rootPaths: [first.path, root.appendingPathComponent("missing").path, second.path, root.path, first.path]
        )
        #expect(found.map(\.lastPathComponent) == ["alpha", "beta"])
    }
}
