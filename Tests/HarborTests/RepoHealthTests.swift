import Foundation
@testable import HarborCore
import Testing

struct RepoHealthTests {
    private static let sha = String(repeating: "a1b2c3d4e5", count: 4)

    private static func inputs(
        alerts: RepoSecurity = RepoSecurity(dependabot: DependabotTally(critical: 0, high: 0, medium: 0, low: 0), secretLeaks: 0, codeScanning: 0),
        policy: Bool? = true,
        reporting: Bool? = true,
        hardening: HardeningChecklist = clean,
        failing: Bool? = false,
        stale: Int? = 0
    ) -> RepoHealthInputs {
        RepoHealthInputs(
            defaultBranch: "main",
            alerts: alerts,
            hasSecurityPolicy: policy,
            privateReporting: reporting,
            hardening: hardening,
            latestRunFailing: failing,
            stalePullRequests: stale
        )
    }

    private static let clean = HardeningChecklist(
        branch: BranchProtectionState(pullRequestRequired: true, statusChecksRequired: true, forcePushBlocked: true),
        signedCommits: true,
        unpinnedActions: 0,
        workflowDefaultsToRead: true,
        dependabotUpdates: true
    )

    // MARK: Scoring

    @Test
    func cleanRepoIsAnA() {
        let score = RepoHealthScorer.score(Self.inputs())
        #expect(score.points == 100)
        #expect(score.grade == .a)
        #expect(score.reason == "A · nothing dragging it down")
    }

    @Test
    func reasonListsTheTopDragsLargestFirst() {
        var hardening = Self.clean
        hardening.branch = BranchProtectionState(pullRequestRequired: false, statusChecksRequired: true, forcePushBlocked: true)
        let alerts = RepoSecurity(dependabot: DependabotTally(critical: 0, high: 2, medium: 0, low: 0), secretLeaks: 0, codeScanning: 0)
        let score = RepoHealthScorer.score(Self.inputs(alerts: alerts, hardening: hardening))
        #expect(score.points == 84)
        #expect(score.grade == .b)
        #expect(score.reason == "B · main not protected, 2 high alerts")
    }

    @Test
    func unknownInputsCostNothingAndAreCounted() {
        let blind = RepoHealthInputs(
            defaultBranch: "main",
            alerts: RepoSecurity(dependabot: nil, secretLeaks: nil, codeScanning: nil),
            hasSecurityPolicy: nil,
            privateReporting: nil,
            hardening: HardeningChecklist(),
            latestRunFailing: nil,
            stalePullRequests: nil
        )
        let score = RepoHealthScorer.score(blind)
        #expect(score.points == 100)
        #expect(score.grade == .a)
        #expect(score.notVisible == 10)
        #expect(score.reason == "A · nothing dragging it down · 10 not visible")
    }

    @Test
    func aKnownBadValueStillCountsWhenOthersAreHidden() {
        var hardening = HardeningChecklist()
        hardening.signedCommits = false
        let score = RepoHealthScorer.score(Self.inputs(alerts: RepoSecurity(dependabot: nil, secretLeaks: nil, codeScanning: nil), hardening: hardening))
        #expect(score.points == 96)
        #expect(score.drags == [HealthDrag(label: "unsigned commits allowed", points: 4)])
    }

    @Test
    func aLeakedSecretDropsThirty() {
        let alerts = RepoSecurity(dependabot: DependabotTally(critical: 0, high: 0, medium: 0, low: 0), secretLeaks: 1, codeScanning: 0)
        let score = RepoHealthScorer.score(Self.inputs(alerts: alerts))
        #expect(score.points == 70)
        #expect(score.grade == .c)
        #expect(score.reason == "C · 1 leaked secret")
    }

    @Test
    func severityPenaltiesAreCapped() {
        let alerts = RepoSecurity(dependabot: DependabotTally(critical: 10, high: 10, medium: 10, low: 10), secretLeaks: 0, codeScanning: 50)
        let score = RepoHealthScorer.score(Self.inputs(alerts: alerts))
        #expect(score.drags.map(\.points) == [30, 15, 10, 5])
        #expect(score.points == 40)
        #expect(score.grade == .f)
    }

    @Test
    func gradeBoundaries() {
        let expected: [(Int, HealthGrade)] = [(100, .a), (90, .a), (89, .b), (80, .b), (79, .c), (70, .c), (69, .d), (60, .d), (59, .f), (0, .f)]
        for (points, grade) in expected {
            #expect(RepoHealthScorer.grade(for: points) == grade, "points \(points)")
        }
    }

    @Test
    func missingChecksOnlyCountWhenPullRequestsAreRequired() {
        var hardening = Self.clean
        hardening.branch = BranchProtectionState(pullRequestRequired: true, statusChecksRequired: false, forcePushBlocked: true)
        #expect(RepoHealthScorer.score(Self.inputs(hardening: hardening)).drags == [HealthDrag(label: "no required checks", points: 4)])
    }

    @Test
    func stalePullRequestsAndFailingCIDrag() {
        let score = RepoHealthScorer.score(Self.inputs(failing: true, stale: 5))
        #expect(score.drags == [HealthDrag(label: "CI failing", points: 4), HealthDrag(label: "5 stale PRs", points: 3)])
    }

    // MARK: Checklist states

    @Test
    func checklistKeepsUnknownApartFromFail() {
        #expect(HardeningChecklist().branchProtection == .unknown)
        #expect(HardeningChecklist(branch: BranchProtectionState(pullRequestRequired: false)).branchProtection == .fail)
        #expect(Self.clean.branchProtection == .pass)
        #expect(HardeningChecklist(unpinnedActions: 0).pinnedActionsState == .pass)
        #expect(HardeningChecklist(unpinnedActions: 2).pinnedActionsState == .fail)
        #expect(HardeningChecklist().pinnedActionsState == .unknown)
    }

    @Test
    func rulesetsAndClassicProtectionAreCombined() {
        let rules: Set<String> = ["pull_request", "non_fast_forward", "required_signatures"]
        let viaRules = BranchProtectionEvaluator.evaluate(ruleTypes: rules, classic: .unknown)
        #expect(viaRules.branch == BranchProtectionState(pullRequestRequired: true, statusChecksRequired: nil, forcePushBlocked: true))
        #expect(viaRules.signedCommits == true)

        let adminNothing = BranchProtectionEvaluator.evaluate(ruleTypes: [], classic: .absent)
        #expect(adminNothing.branch == BranchProtectionState(pullRequestRequired: false, statusChecksRequired: false, forcePushBlocked: false))
        #expect(adminNothing.signedCommits == false)

        let classic = ClassicProtectionLookup.present(requiresPullRequest: false, requiresStatusChecks: true, blocksForcePush: true, requiresSignatures: false)
        let mixed = BranchProtectionEvaluator.evaluate(ruleTypes: ["pull_request"], classic: classic)
        #expect(mixed.branch == BranchProtectionState(pullRequestRequired: true, statusChecksRequired: true, forcePushBlocked: true))
        #expect(mixed.signedCommits == false)

        let blind = BranchProtectionEvaluator.evaluate(ruleTypes: nil, classic: .unknown)
        #expect(blind.branch == BranchProtectionState())
        #expect(blind.signedCommits == nil)
    }

    // MARK: Pinned actions

    @Test
    func pinnedUsesVariants() {
        let sha = Self.sha
        let workflow = """
        jobs:
          build:
            steps:
              - uses: actions/checkout@\(sha) # v4.1.1
              - uses: actions/setup-node@v4
              - uses: ./.github/actions/local
              - uses: ./
              - uses: docker://alpine:3.19
              - uses: "actions/cache@v4"
              - uses: 'actions/upload-artifact@\(sha)'
              - uses: owner/repo/.github/workflows/x.yml@main
              - uses: actions/short@\(sha.dropLast())
              - uses: actions/long@\(sha)0
              - uses: actions/nothex@\(String(repeating: "g", count: 40))
              - uses: actions/noref
              - run: echo uses: not/a-step@v1
                uses: actions/indented@v2
        """
        #expect(ActionPinChecker.unpinnedUses(in: workflow) == [
            "actions/setup-node@v4",
            "actions/cache@v4",
            "owner/repo/.github/workflows/x.yml@main",
            "actions/short@\(sha.dropLast())",
            "actions/long@\(sha)0",
            "actions/nothex@\(String(repeating: "g", count: 40))",
            "actions/noref",
            "actions/indented@v2"
        ])
    }

    @Test
    func isPinnedAcceptsOnlyFortyHex() {
        #expect(ActionPinChecker.isPinned("actions/checkout@\(Self.sha)"))
        #expect(ActionPinChecker.isPinned("actions/checkout@\(Self.sha.uppercased())"))
        #expect(ActionPinChecker.isPinned("./local"))
        #expect(ActionPinChecker.isPinned("../shared"))
        #expect(ActionPinChecker.isPinned("docker://ghcr.io/x/y:1"))
        #expect(!ActionPinChecker.isPinned("actions/checkout@v4"))
        #expect(!ActionPinChecker.isPinned("actions/checkout@main"))
    }

    // MARK: Dependabot

    @Test
    func aggregationCountsEverythingAndListsTheWorstThree() {
        let findings = [
            DependabotFinding(package: "zeta", severity: "low", patchedVersion: "1.0.1"),
            DependabotFinding(package: "lodash", severity: "high", patchedVersion: "4.17.21"),
            DependabotFinding(package: "lodash", severity: "high", patchedVersion: "4.17.21"),
            DependabotFinding(package: "alpha", severity: "critical", patchedVersion: nil),
            DependabotFinding(package: "beta", severity: "medium", patchedVersion: "2.0.0"),
            DependabotFinding(package: "axios", severity: "high", patchedVersion: "1.6.0"),
            DependabotFinding(package: "odd", severity: "unheard-of", patchedVersion: "9")
        ]
        let result = DependabotAggregation.aggregate(findings)
        #expect(result.tally == DependabotTally(critical: 1, high: 3, medium: 1, low: 1))
        #expect(result.worst.map(\.line) == ["alpha → no patch", "axios → 1.6.0", "lodash → 4.17.21"])
    }

    @Test
    func aggregationOfNothingIsZero() {
        let result = DependabotAggregation.aggregate([])
        #expect(result.tally == DependabotTally(critical: 0, high: 0, medium: 0, low: 0))
        #expect(result.worst.isEmpty)
    }

    // MARK: Settings URLs

    @Test
    func settingsURLs() throws {
        let web = try #require(URL(string: "https://github.com"))
        func url(_ fix: HardeningFix) -> String {
            RepoSettingsURL.url(webBase: web, owner: "sriinnu", name: "harbor", fix: fix, defaultBranch: "main").absoluteString
        }
        #expect(url(.branchProtection) == "https://github.com/sriinnu/harbor/settings/branches")
        #expect(url(.signedCommits) == "https://github.com/sriinnu/harbor/settings/branches")
        #expect(url(.workflowPermissions) == "https://github.com/sriinnu/harbor/settings/actions")
        #expect(url(.dependabotUpdates) == "https://github.com/sriinnu/harbor/settings/security_analysis")
        #expect(url(.privateReporting) == "https://github.com/sriinnu/harbor/settings/security_analysis")
        #expect(url(.pinnedActions) == "https://github.com/sriinnu/harbor/tree/main/.github/workflows")
        #expect(url(.securityPolicy) == "https://github.com/sriinnu/harbor/security/policy")
        #expect(RepoSettingsURL.path(for: .pinnedActions, defaultBranch: "trunk") == "tree/trunk/.github/workflows")
    }

    @Test
    func webBaseFollowsTheAPIHost() throws {
        #expect(RepoSettingsURL.webBase(fromAPIHost: try #require(URL(string: "https://api.github.com"))).absoluteString == "https://github.com")
        #expect(RepoSettingsURL.webBase(fromAPIHost: try #require(URL(string: "https://ghe.example.com/api/v3"))).absoluteString == "https://ghe.example.com")
    }

    // MARK: Flow

    @Test
    func reviewStateUsesTheLatestVerdictPerReviewer() {
        typealias Review = (user: String, state: String)
        func derive(_ reviews: [Review], draft: Bool = false, requested: Bool = false) -> PullReviewState {
            PullReviewState.derive(isDraft: draft, reviews: reviews, hasRequestedReviewers: requested)
        }
        #expect(derive([("a", "APPROVED")], draft: true) == .draft)
        #expect(derive([("a", "APPROVED")]) == .approved)
        #expect(derive([("a", "CHANGES_REQUESTED"), ("b", "APPROVED")]) == .changesRequested)
        #expect(derive([("a", "CHANGES_REQUESTED"), ("a", "APPROVED")]) == .approved)
        #expect(derive([("a", "APPROVED"), ("a", "DISMISSED")]) == .noReviews)
        #expect(derive([("a", "COMMENTED")], requested: true) == .reviewRequested)
        #expect(derive([]) == .noReviews)
    }

    @Test
    func pullStalenessIsStrictlyOverSevenDays() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        func pull(ageDays: Double) -> FlowPullRequest {
            FlowPullRequest(number: 1, title: "t", createdAt: now.addingTimeInterval(-ageDays * 86400), review: .noReviews)
        }
        #expect(!pull(ageDays: 7).isStale(now: now))
        #expect(pull(ageDays: 7.01).isStale(now: now))
        #expect(pull(ageDays: 3).ageLabel(now: now) == "3d")
        #expect(pull(ageDays: 0.25).ageLabel(now: now) == "6h")
        #expect(pull(ageDays: 0).ageLabel(now: now) == "1m")
    }

    @Test
    func runDurations() {
        let runs = [
            FlowRun(status: .passing, duration: 60),
            FlowRun(status: .failing, duration: 200),
            FlowRun(status: .pending, duration: nil)
        ]
        #expect(FlowRun.averageDuration(runs) == 130)
        #expect(FlowRun.averageDuration([FlowRun(status: .pending, duration: nil)]) == nil)
        #expect(FlowRun.durationLabel(45) == "45s")
        #expect(FlowRun.durationLabel(134) == "2m 14s")
        #expect(FlowRun.durationLabel(3900) == "1h 05m")
    }
}

// MARK: - Code scanning wording

struct CodeScanningWordingTests {
    private func section(codeScanning: Int?, availability: AlertAvailability? = nil) -> RepoSecuritySection {
        RepoSecuritySection(
            alerts: RepoSecurity(dependabot: nil, secretLeaks: nil, codeScanning: codeScanning),
            topAlerts: [], hasSecurityPolicy: nil, privateReporting: nil, codeScanning: availability
        )
    }

    @Test
    func aNotFoundIsNotEnabledWithAHintAndAForbiddenIsNeedsAdmin() {
        #expect(AlertAvailability(withheldStatus: 404) == .notEnabled)
        #expect(AlertAvailability(withheldStatus: 403) == .needsAdmin)

        let notEnabled = self.section(codeScanning: nil, availability: AlertAvailability(withheldStatus: 404))
        #expect(notEnabled.codeScanningValue == "Not enabled")
        #expect(notEnabled.codeScanningHint == "Turn on CodeQL in Settings → Code security")

        let forbidden = self.section(codeScanning: nil, availability: AlertAvailability(withheldStatus: 403))
        #expect(forbidden.codeScanningValue == "not visible (needs admin)")
        #expect(forbidden.codeScanningHint == nil)
    }

    @Test
    func aCountIsShownAsIsAndAnUnexplainedMissingCountMeansNeedsAdmin() {
        let counted = self.section(codeScanning: 3)
        #expect(counted.codeScanning == .visible)
        #expect(counted.codeScanningValue == "3")
        #expect(counted.codeScanningHint == nil)
        #expect(self.section(codeScanning: 0).codeScanningValue == "0")
        let unknown = self.section(codeScanning: nil)
        #expect(unknown.codeScanning == .needsAdmin)
        #expect(unknown.codeScanningValue == "not visible (needs admin)")
    }
}
