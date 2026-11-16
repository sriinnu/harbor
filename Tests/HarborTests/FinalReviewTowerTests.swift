import Foundation
@testable import HarborCore
import Testing

/// The final review's Tower findings: the sandbox's reach, old git, and honest "not checked".
struct FinalReviewTowerTests {
    // MARK: 5. an alternate object store is not written either

    /// `clone --shared` leaves `objects/info/alternates` pointing at the source repo. A merge
    /// that "writes" a tree git already has freshens it (`utime`) wherever it lives, the source
    /// repo's pack included, unless every write outside the scratch directory is denied.
    @Test
    func forecast_aRepoNamedInAlternatesKeepsItsPackModificationTimes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tower-alt-\(UUID().uuidString)").resolvingSymlinksInPath()
        let source = root.appendingPathComponent("source")
        let clone = root.appendingPathComponent("clone")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try TowerFixture.runGit(["init", "-b", "main"], in: source)
        try TowerFixture.runGit(["config", "core.hooksPath", "/dev/null"], in: source)
        try TowerFixture.runGit(["config", "commit.gpgsign", "false"], in: source)
        try TowerFixture.commit("a.txt", "base\n", "base", in: source)
        try TowerFixture.runGit(["checkout", "-b", "packed"], in: source)
        try TowerFixture.commit("b.txt", "packed\n", "p", in: source)
        try TowerFixture.runGit(["checkout", "main"], in: source)
        try TowerFixture.runGit(["repack", "-a", "-d", "-q"], in: source)
        try TowerFixture.runGit(["clone", "--shared", "-q", source.path, clone.path], in: root)
        let alternates = try String(contentsOf: clone.appendingPathComponent(".git/objects/info/alternates"), encoding: .utf8)
        #expect(alternates.trimmingCharacters(in: .whitespacesAndNewlines) == source.appendingPathComponent(".git/objects").path)

        let packs = source.appendingPathComponent(".git/objects/pack")
        func mtimes() throws -> [String: Date] {
            var result: [String: Date] = [:]
            for name in try FileManager.default.contentsOfDirectory(atPath: packs.path) {
                result[name] = try FileManager.default.attributesOfItem(atPath: packs.appendingPathComponent(name).path)[.modificationDate] as? Date
            }
            return result
        }
        let before = try mtimes()
        #expect(before.keys.contains { $0.hasSuffix(".pack") })
        Thread.sleep(forTimeInterval: 1.1)
        let git = try #require(TowerGit())
        let result = ConflictForecast.run(
            git: git, repo: clone.path, objectsDirectory: clone.appendingPathComponent(".git/objects").path,
            base: "main", head: "refs/remotes/origin/packed"
        )
        #expect(result == .clean)
        #expect(try mtimes() == before)
    }

    @Test
    func forecast_sandboxProfileDeniesEveryWriteExceptTheScratchAndDevNull() {
        #expect(ConflictForecast.sandboxArguments(allowingWritesTo: "/tmp/a b") == [
            "-D", "S=/private/tmp/a b", "-p",
            "(version 1)(allow default)(deny file-write*)(allow file-write* (subpath (param \"S\")) (literal \"/dev/null\"))"
        ])
    }

    // MARK: 4. git without %(ahead-behind:) keeps its counts

    /// A git that refuses the `%(ahead-behind:)` format, as git before 2.41 does; everything
    /// else is the real git.
    private func oldGit(in root: URL) throws -> TowerGit {
        let script = root.appendingPathComponent("old-git")
        try Data("""
        #!/bin/sh
        case "$*" in
          *ahead-behind*) exit 129;;
        esac
        exec /usr/bin/git "$@"
        """.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return try #require(TowerGit(locator: FixedLocator(url: script)))
    }

    @Test
    func scanner_withoutAheadBehindFormatStillCountsEveryBranch() throws {
        let fixture = try TowerFixture()
        defer { fixture.remove() }
        let git = try self.oldGit(in: fixture.root)
        let scanner = TowerScanner(git: git, home: fixture.root.path, host: "h", now: Date(), probe: NeverAlive())
        let final = try #require(scanner.scan(repo: fixture.repo.path, ledger: [:]) { _ in })
        let byBranch = Dictionary(uniqueKeysWithValues: final.rows.map { ($0.branch ?? "", $0) })
        for branch in ["feat-a", "feat-b", "feat-clean"] {
            let row = try #require(byBranch[branch])
            #expect(row.ahead == 1)
            #expect(row.behind == 1)
            #expect(row.lastActivity != nil)
        }
        #expect(try #require(byBranch["feat-clean"]).lane == .ready)
    }

    @Test
    func parse_branchDatesReadsRefAndTime() {
        let raw = "refs/heads/feat/x\t1762800000\nrefs/heads/main\t1762800100\nbroken\n"
        #expect(TowerGitParse.branchDates(raw) == [
            "feat/x": Date(timeIntervalSince1970: 1_762_800_000),
            "main": Date(timeIntervalSince1970: 1_762_800_100)
        ])
    }

    // MARK: 7. no forecast is "not checked", not "0 would conflict"

    @Test
    func mainMovedText_rowsWithoutAForecastAreNotChecked() throws {
        let fixture = try TowerFixture()
        defer { fixture.remove() }
        let git = try #require(TowerGit())
        let scanner = TowerScanner(git: git, home: fixture.root.path, host: "h", now: Date(), probe: NeverAlive(), forecastSupported: false)
        let final = try #require(scanner.scan(repo: fixture.repo.path, ledger: [:]) { _ in })
        #expect(final.mainMovedText == "main moved: 3 behind, not checked")
    }

    private func row(_ name: String, behind: Int, forecast: MergeForecast?) -> TowerRow {
        TowerRow(
            repoPath: "/r", repoName: "r", path: "/r/\(name)", branch: name, agent: nil, task: nil, note: nil, evidence: nil,
            build: nil, delivered: nil, advice: nil, isLocked: false, isPrunable: false, ahead: 1, behind: behind, dirty: 0,
            forecast: forecast, collisions: [], lastActivity: nil, timeline: [], lane: .ready, reason: ""
        )
    }

    private func snapshot(_ rows: [TowerRow]) -> TowerRepoSnapshot {
        TowerRepoSnapshot(path: "/r", name: "r", base: "main", rows: rows, collisions: [], phase: .forecast)
    }

    @Test
    func mainMovedText_countsUnknownAndNilSeparatelyFromCleanAndConflicting() {
        let mixed = self.snapshot([
            self.row("a", behind: 1, forecast: .conflicts(["x"])), self.row("b", behind: 1, forecast: .clean),
            self.row("c", behind: 1, forecast: .unknown), self.row("d", behind: 1, forecast: nil)
        ])
        #expect(mixed.mainMovedText == "main moved: 4 behind, 1 would conflict, 2 not checked")
        let unknown = self.snapshot([self.row("a", behind: 2, forecast: .unknown)])
        #expect(unknown.mainMovedText == "main moved: 1 behind, not checked")
        let checked = self.snapshot([self.row("a", behind: 2, forecast: .clean), self.row("b", behind: 1, forecast: .conflicts(["x"]))])
        #expect(checked.mainMovedText == "main moved: 2 behind, 1 would conflict")
    }
}
