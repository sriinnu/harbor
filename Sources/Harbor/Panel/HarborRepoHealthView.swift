import HarborCore
import SwiftUI

private let alertRed = Color(hex: 0xE5484D)
private let notVisibleText = "not visible (needs admin)"

/// Health score, security, hardening and flow for one repo, below the detail header.
/// Each section shows a skeleton until its data arrives.
struct HarborRepoHealthView: View {
    let model: RepoHealthModel
    let cleanup: RunCleanupModel
    let repo: RepositoryDisplayModel
    let open: (String) -> Void
    /// Opens a pull request's pane by number.
    var openPull: (Int) -> Void = { _ in }
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HealthScorePlate(score: self.model.score(), isLoading: self.model.isLoading)
            PanelSeparator()
            if let note = self.model.note {
                Text(note)
                    .font(.system(size: self.skin.row.detailSize))
                    .foregroundStyle(self.skin.secondaryText)
                    .padding(.horizontal, self.skin.row.itemPadding)
                    .padding(.bottom, 4)
            }
            HealthSecuritySection(section: self.model.security, isLoading: self.model.isLoading, open: self.open, fix: self.fixPath)
            PanelSeparator()
            HealthHardeningSection(checklist: self.model.hardening, isLoading: self.model.isLoading, open: self.open, fix: self.fixPath)
            PanelSeparator()
            HealthFlowSection(
                flow: self.model.flow, isLoading: self.model.isLoading, repoPulls: self.repo.pulls,
                cleanup: self.cleanup, fullName: self.repo.title, open: self.open, openPull: self.openPull
            )
            PanelSeparator()
        }
    }

    private func fixPath(_ fix: HardeningFix) -> String {
        RepoSettingsURL.path(for: fix, defaultBranch: self.model.basics?.defaultBranch ?? "main")
    }
}

// MARK: - Shared bits

struct SectionTitle: View {
    let text: String
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        Text(self.text)
            .font(.system(size: self.skin.row.detailSize, weight: .semibold))
            .foregroundStyle(self.skin.secondaryText)
            .padding(.horizontal, self.skin.row.itemPadding)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct Skeleton: View {
    var width: CGFloat?
    var height: CGFloat = 10
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(self.skin.tertiaryText.opacity(0.25))
            .frame(width: self.width, height: self.height)
            .accessibilityHidden(true)
    }
}

struct SkeletonLines: View {
    let count: Int
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(0 ..< self.count, id: \.self) { index in Skeleton(width: index.isMultiple(of: 2) ? 220 : 150) }
        }
        .padding(.horizontal, self.skin.row.itemPadding)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

/// A plain line of the card: a title, and a value or note on the right.
private struct HealthLine: View {
    let title: String
    let value: String
    var valueColor: Color?
    var symbol: String?
    var symbolColor: Color?
    /// The tick, cross or dash as words: the symbol is hidden from VoiceOver.
    var status: String?
    @Environment(\.menuItemHighlighted) private var isHighlighted
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: self.symbol ?? "circle")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 16)
                .opacity(self.symbol == nil ? 0 : 1)
                .foregroundStyle(self.isHighlighted ? self.skin.selectionText : (self.symbolColor ?? self.skin.secondaryText))
                .accessibilityHidden(true)
            Text(self.title)
                .foregroundStyle(self.isHighlighted ? self.skin.selectionText : self.skin.text)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(self.value)
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(self.isHighlighted ? self.skin.selectionText : (self.valueColor ?? self.skin.secondaryText))
        }
        .font(.system(size: self.skin.row.nameSize))
        .padding(.horizontal, self.skin.row.itemPadding)
        .frame(height: self.skin.itemHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(self.title)
        .accessibilityValue([self.status, self.value].compactMap(\.self).filter { !$0.isEmpty }.joined(separator: ", "))
    }
}

// MARK: - Score

private struct HealthScorePlate: View {
    let score: RepoHealthScore?
    let isLoading: Bool
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        HStack(spacing: 10) {
            self.ring
            VStack(alignment: .leading, spacing: 2) {
                Text("Health")
                    .font(.system(size: self.skin.row.nameSize, weight: .semibold))
                    .foregroundStyle(self.skin.text)
                if let score {
                    Text(score.reason)
                        .font(.system(size: self.skin.row.detailSize))
                        .foregroundStyle(self.skin.secondaryText)
                        .lineLimit(2)
                } else if self.isLoading {
                    Skeleton(width: 190)
                } else {
                    Text("Unavailable")
                        .font(.system(size: self.skin.row.detailSize))
                        .foregroundStyle(self.skin.secondaryText)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, self.skin.row.itemPadding)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(self.score.map { "Health grade \($0.reason)" } ?? "Health loading")
    }

    private var ring: some View {
        let color = self.color
        return ZStack {
            Circle().stroke(self.skin.tertiaryText.opacity(0.25), lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(self.score?.points ?? 0) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(self.score?.grade.rawValue ?? "·")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(self.score == nil ? self.skin.tertiaryText : color)
        }
        .frame(width: 34, height: 34)
    }

    private var color: Color {
        switch self.score?.grade {
        case .a, .b: self.skin.ok.text
        case .c, .d: self.skin.warn.text
        case .f: alertRed
        case nil: self.skin.tertiaryText
        }
    }
}

// MARK: - Security

private struct HealthSecuritySection: View {
    let section: RepoSecuritySection?
    let isLoading: Bool
    let open: (String) -> Void
    let fix: (HardeningFix) -> String
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle(text: "Security")
            if let section {
                self.content(section)
            } else if self.isLoading {
                SkeletonLines(count: 4)
            }
        }
    }

    @ViewBuilder
    private func content(_ section: RepoSecuritySection) -> some View {
        if let secrets = section.alerts.secretLeaks, secrets > 0 {
            PanelRow(id: "health:secrets", action: { self.open("security/secret-scanning") }) {
                HealthLine(
                    title: "\(secrets) leaked secret\(secrets == 1 ? "" : "s")",
                    value: "open",
                    valueColor: alertRed,
                    symbol: "exclamationmark.triangle.fill",
                    symbolColor: alertRed,
                    status: "warning"
                )
            }
            .accessibilityHint("Opens secret scanning on GitHub")
        }
        self.dependabot(section)
        if let hint = section.codeScanningHint {
            PanelRow(id: "health:codescanning", action: { self.open("settings/security_analysis") }) {
                HealthLine(title: "Code scanning", value: section.codeScanningValue)
            }
            .help(hint)
            Text(hint)
                .font(.system(size: self.skin.row.detailSize))
                .foregroundStyle(self.skin.tertiaryText)
                .padding(.leading, self.skin.row.itemPadding + 24)
                .padding(.trailing, self.skin.row.itemPadding)
                .padding(.bottom, 2)
        } else {
            HealthLine(title: "Code scanning", value: section.codeScanningValue)
        }
        if section.alerts.secretLeaks.map({ $0 == 0 }) != false {
            HealthLine(title: "Secret scanning", value: Self.count(section.alerts.secretLeaks))
        }
        CheckLine(
            title: "SECURITY.md",
            state: Self.state(section.hasSecurityPolicy),
            detail: nil,
            open: { self.open(self.fix(.securityPolicy)) },
            id: "health:policy"
        )
        CheckLine(
            title: "Private vulnerability reporting",
            state: Self.state(section.privateReporting),
            detail: nil,
            open: { self.open(self.fix(.privateReporting)) },
            id: "health:pvr"
        )
    }

    @ViewBuilder
    private func dependabot(_ section: RepoSecuritySection) -> some View {
        if let tally = section.alerts.dependabot {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text("Dependabot")
                        .font(.system(size: self.skin.row.nameSize))
                        .foregroundStyle(self.skin.text)
                    Spacer(minLength: 4)
                    SeverityChip(label: "critical", count: tally.critical, color: alertRed)
                    SeverityChip(label: "high", count: tally.high, color: Color(hex: 0xF76B15))
                    SeverityChip(label: "medium", count: tally.medium, color: Color(hex: 0xD9A400))
                    SeverityChip(label: "low", count: tally.low, color: self.skin.secondaryText)
                }
                ForEach(section.topAlerts, id: \.self) { finding in
                    Text("\(finding.line)")
                        .font(.system(size: self.skin.row.detailSize, design: .monospaced))
                        .foregroundStyle(self.skin.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.leading, 16)
                }
            }
            .padding(.horizontal, self.skin.row.itemPadding)
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
        } else {
            HealthLine(title: "Dependabot", value: notVisibleText)
        }
    }

    private static func count(_ value: Int?) -> String { value.map(String.init) ?? notVisibleText }

    static func state(_ value: Bool?) -> CheckState {
        switch value {
        case true: .pass
        case false: .fail
        case nil: .unknown
        }
    }
}

private struct SeverityChip: View {
    let label: String
    let count: Int
    let color: Color
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        Text("\(self.count) \(self.label)")
            .font(.system(size: self.skin.row.detailSize - 1, weight: .semibold))
            .foregroundStyle(self.count > 0 ? self.color : self.skin.tertiaryText)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4).fill((self.count > 0 ? self.color : self.skin.tertiaryText).opacity(0.15)))
            .accessibilityLabel("\(self.count) \(self.label) alerts")
    }
}

// MARK: - Hardening

/// A check with a ✓ or ✗. A ✗ is a row that opens the page that fixes it.
private struct CheckLine: View {
    let title: String
    let state: CheckState
    let detail: String?
    let open: () -> Void
    let id: String
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        switch self.state {
        case .pass:
            HealthLine(title: self.title, value: self.detail ?? "", symbol: "checkmark", symbolColor: self.skin.ok.text, status: "in place")
        case .unknown:
            HealthLine(
                title: self.title, value: notVisibleText, valueColor: self.skin.tertiaryText,
                symbol: "minus", symbolColor: self.skin.tertiaryText, status: "unknown"
            )
        case .fail:
            PanelRow(id: self.id, action: self.open) {
                HealthLine(
                    title: self.title,
                    value: self.detail ?? "fix",
                    valueColor: self.skin.warn.text,
                    symbol: "xmark",
                    symbolColor: alertRed,
                    status: "missing"
                )
            }
            .help("Open the GitHub setting that fixes this")
            .accessibilityHint("Opens the GitHub setting that fixes this")
        }
    }
}

private struct HealthHardeningSection: View {
    let checklist: HardeningChecklist?
    let isLoading: Bool
    let open: (String) -> Void
    let fix: (HardeningFix) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle(text: "Hardening")
            if let checklist {
                self.rows(checklist)
            } else if self.isLoading {
                SkeletonLines(count: 5)
            }
        }
    }

    @ViewBuilder
    private func rows(_ list: HardeningChecklist) -> some View {
        CheckLine(
            title: "Default branch protected",
            state: list.branchProtection,
            detail: Self.missing(list.branch),
            open: { self.open(self.fix(.branchProtection)) },
            id: "health:branch"
        )
        CheckLine(
            title: "Signed commits required",
            state: list.signedCommitsState,
            detail: nil,
            open: { self.open(self.fix(.signedCommits)) },
            id: "health:signed"
        )
        CheckLine(
            title: "Actions pinned to SHAs",
            state: list.pinnedActionsState,
            detail: list.unpinnedActions.map { "\($0) unpinned" },
            open: { self.open(self.fix(.pinnedActions)) },
            id: "health:pins"
        )
        CheckLine(
            title: "Workflow token defaults to read",
            state: list.workflowPermissionsState,
            detail: nil,
            open: { self.open(self.fix(.workflowPermissions)) },
            id: "health:perms"
        )
        CheckLine(
            title: "Dependabot security updates",
            state: list.dependabotUpdatesState,
            detail: nil,
            open: { self.open(self.fix(.dependabotUpdates)) },
            id: "health:updates"
        )
    }

    /// What is missing on the branch, e.g. "no PRs, no checks".
    private static func missing(_ branch: BranchProtectionState) -> String? {
        var gaps: [String] = []
        if branch.pullRequestRequired == false { gaps.append("no PRs") }
        if branch.statusChecksRequired == false { gaps.append("no checks") }
        if branch.forcePushBlocked == false { gaps.append("force-push") }
        return gaps.isEmpty ? nil : gaps.joined(separator: ", ")
    }
}

// MARK: - Flow

private struct HealthFlowSection: View {
    let flow: RepoFlowSection?
    let isLoading: Bool
    let repoPulls: Int
    let cleanup: RunCleanupModel
    let fullName: String
    let open: (String) -> Void
    let openPull: (Int) -> Void
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle(text: "Flow")
            if let flow {
                self.content(flow)
            } else if self.isLoading {
                SkeletonLines(count: 4)
            }
        }
    }

    @ViewBuilder
    private func content(_ flow: RepoFlowSection) -> some View {
        if flow.pulls.isEmpty {
            HealthLine(title: "No open PRs", value: "")
        } else {
            ForEach(flow.pulls, id: \.number) { pull in
                PanelRow(id: "health:pr:\(pull.number)", action: { self.openPull(pull.number) }) {
                    PullLine(pull: pull)
                }
            }
            if self.repoPulls > flow.pulls.count {
                Text("+\(self.repoPulls - flow.pulls.count) more")
                    .font(.system(size: self.skin.row.detailSize))
                    .foregroundStyle(self.skin.tertiaryText)
                    .padding(.horizontal, self.skin.row.itemPadding)
            }
        }
        PanelRow(id: "health:runs", action: { self.open("actions") }) { RunsLine(runs: flow.runs) }
        RunCleanupRows(model: self.cleanup, fullName: self.fullName)
        PanelRow(id: "health:release", action: { self.open("releases") }) {
            HealthLine(
                title: flow.release?.tag ?? "No releases",
                value: flow.commitsSinceRelease.map { "\($0) commit\($0 == 1 ? "" : "s") since" } ?? "",
                symbol: "tag"
            )
        }
    }
}

private struct PullLine: View {
    let pull: FlowPullRequest
    @Environment(\.menuItemHighlighted) private var isHighlighted
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        let stale = self.pull.isStale(now: Date())
        let muted = self.isHighlighted ? self.skin.selectionText : self.skin.secondaryText
        HStack(spacing: 6) {
            Text("#\(self.pull.number)")
                .monospacedDigit()
                .foregroundStyle(muted)
            Text(self.pull.title)
                .foregroundStyle(self.isHighlighted ? self.skin.selectionText : self.skin.text)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Text(self.pull.review.label)
                .foregroundStyle(self.reviewColor(muted))
            Text(stale ? "\(self.pull.ageLabel(now: Date())) stale" : self.pull.ageLabel(now: Date()))
                .monospacedDigit()
                .foregroundStyle(stale && !self.isHighlighted ? self.skin.warn.text : muted)
        }
        .font(.system(size: self.skin.row.nameSize))
        .padding(.horizontal, self.skin.row.itemPadding)
        .frame(height: self.skin.itemHeight)
    }

    private func reviewColor(_ muted: Color) -> Color {
        guard !self.isHighlighted else { return muted }
        switch self.pull.review {
        case .approved: return self.skin.ok.text
        case .changesRequested: return alertRed
        default: return muted
        }
    }
}

private struct RunsLine: View {
    let runs: [FlowRun]
    @Environment(\.menuItemHighlighted) private var isHighlighted
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "play.circle")
                .font(.system(size: 11))
                .frame(width: 16)
                .foregroundStyle(self.isHighlighted ? self.skin.selectionText : self.skin.secondaryText)
            if self.runs.isEmpty {
                Text("No workflow runs").foregroundStyle(self.isHighlighted ? self.skin.selectionText : self.skin.text)
            } else {
                HStack(spacing: 4) {
                    ForEach(Array(self.runs.enumerated()), id: \.offset) { _, run in
                        StatusGlyph(kind: StatusGlyph.Kind(run.status), size: 12)
                    }
                }
            }
            Spacer(minLength: 4)
            if let average = FlowRun.averageDuration(self.runs) {
                Text("avg \(FlowRun.durationLabel(average))")
                    .monospacedDigit()
                    .foregroundStyle(self.isHighlighted ? self.skin.selectionText : self.skin.secondaryText)
            }
        }
        .font(.system(size: self.skin.row.nameSize))
        .padding(.horizontal, self.skin.row.itemPadding)
        .frame(height: self.skin.itemHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Last \(self.runs.count) workflow runs")
        .accessibilityValue(self.runs.map { StatusGlyph.Kind($0.status).spokenState }.joined(separator: ", "))
    }
}
