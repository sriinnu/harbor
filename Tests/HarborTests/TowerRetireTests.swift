import Foundation
@testable import HarborCore
import Testing

struct TowerRetireTests {
    @Test
    func retireCommand_isDryRunByDefaultWithExactArgv() {
        #expect(RetireCommand.arguments(scripts: "/s", repo: "/r", path: "/r/wt") == [
            "-I", "/s/wtr_retire.py", "worktree", "--repo", "/r", "--path", "/r/wt"
        ])
    }

    @Test
    func retireCommand_executeAddsOnlyTheExecuteFlag() {
        let argv = RetireCommand.arguments(scripts: "/s", repo: "/r", path: "/r/wt", execute: true)
        #expect(argv == ["-I", "/s/wtr_retire.py", "worktree", "--repo", "/r", "--path", "/r/wt", "--execute"])
        #expect(argv.contains("--attest") == false)
        #expect(RetireCommand.arguments(repo: "/r", path: "/p").contains("--execute") == false)
        #expect(RetireCommand.arguments(repo: "/r", path: "/p", execute: true).contains("--attest") == false)
    }

    @Test
    func auditCommand_isReadOnlyJson() {
        #expect(RetireCommand.auditArguments(scripts: "/s", repo: "/r") == ["-I", "/s/wtr_audit.py", "/r", "--json"])
    }

    @Test
    func skillScripts_pointAtTheSkillInTheHomeFolder() {
        #expect(RetireCommand.skillScripts == NSHomeDirectory() + "/.agents/skills/worktree-task-retirement/scripts")
    }

    @Test
    func audit_keepsOnlyCandidates() {
        let json = """
        [
         {"path":"/r","verdict":"KEEP","branch":"main","main_checkout":true},
         {"path":"/w/one","verdict":"CANDIDATE","branch":"feat/one","delivery":"patch-equivalent","idle_days":3},
         {"path":"/w/two","verdict":"STALE-REG"},
         {"path":"/w/three","verdict":"CANDIDATE"},
         {"verdict":"CANDIDATE"}
        ]
        """
        #expect(RetireAudit.candidates(json: json) == [
            RetireCandidate(path: "/w/one", branch: "feat/one", delivery: "patch-equivalent", idleDays: 3),
            RetireCandidate(path: "/w/three", branch: nil, delivery: nil, idleDays: nil)
        ])
        #expect(RetireAudit.candidates(json: "not json").isEmpty)
        #expect(RetireAudit.candidates(json: "{}").isEmpty)
    }
}
