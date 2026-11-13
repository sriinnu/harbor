import AppKit
import HarborCore
import SwiftUI

/// One pull request, slid in over the repo detail: merge readiness in plain words, the
/// conversations to resolve, and the actions to finish it from here.
struct HarborPullDetailPane: View {
    let model: PullDetailModel
    let onBack: () -> Void
    @Environment(\.harborPanelSkin) private var skin
    @Environment(\.panelMaxHeight) private var maxHeight
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        let limit = self.maxHeight - 2 * self.skin.padding
        ScrollView(.vertical, showsIndicators: false) {
            self.content
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { self.contentHeight = $0 })
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: self.contentHeight > 0 ? min(self.contentHeight, limit) : nil)
        .task { await self.model.load() }
        .task(id: self.model.isWatching) { await self.model.poll() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            self.header
            PanelSeparator()
            if let detail = self.model.detail, let readiness = self.model.readiness {
                self.meta(detail)
                PanelSeparator()
                PullReadinessBlock(model: self.model, detail: detail, readiness: readiness)
                if !detail.checks.isEmpty {
                    PanelSeparator()
                    PullChecksSection(checks: detail.checks)
                }
                if !detail.unresolvedThreads.isEmpty {
                    PanelSeparator()
                    PullThreadsSection(model: self.model, threads: detail.unresolvedThreads)
                }
                if detail.state == .open {
                    PanelSeparator()
                    PullActionsSection(model: self.model, detail: detail, readiness: readiness)
                }
                PanelSeparator()
                PanelRow(id: "pull:web", action: { self.openWeb(detail.url) }) {
                    PullLinkLine(title: "Open on GitHub", symbol: "safari")
                }
                .accessibilityHint("Opens the pull request in your browser")
            } else if let error = self.model.loadError {
                PullMessage(text: error, color: MenuInk.status(.fail))
            } else {
                SkeletonLines(count: 5)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button(action: self.onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(self.skin.accent)
            .accessibilityLabel("Back")
            .accessibilityHint("Returns to the repository")
            Image(systemName: "arrow.triangle.pull")
                .font(.system(size: 11))
                .foregroundStyle(self.skin.secondaryText)
                .accessibilityHidden(true)
            Text("#\(self.model.number)")
                .font(.system(size: self.skin.row.nameSize, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(self.skin.text)
            Text("\(self.model.owner)/\(self.model.name)")
                .font(.system(size: self.skin.row.detailSize))
                .foregroundStyle(self.skin.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if self.model.isLoading || self.model.running != nil {
                ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 14, height: 14)
                    .accessibilityLabel(self.model.running != nil ? "Working" : "Loading")
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    private func meta(_ detail: PullRequestDetail) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(detail.title)
                .font(.system(size: self.skin.row.nameSize, weight: .semibold))
                .foregroundStyle(self.skin.text)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 4) {
                if let author = detail.authorLogin {
                    Text("@\(author)")
                    Text("·")
                }
                Text(detail.baseRef).lineLimit(1).truncationMode(.middle)
                Image(systemName: "arrow.left").font(.system(size: 9))
                Text(detail.headRef).lineLimit(1).truncationMode(.middle)
            }
            .font(.system(size: self.skin.row.detailSize))
            .foregroundStyle(self.skin.secondaryText)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(detail.authorLogin ?? "unknown"), \(detail.headRef) into \(detail.baseRef)")
        }
        .padding(.horizontal, self.skin.row.itemPadding)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openWeb(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Readiness

private struct PullReadinessBlock: View {
    let model: PullDetailModel
    let detail: PullRequestDetail
    let readiness: PullReadiness
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle(text: "Merge readiness")
            HStack(alignment: .top, spacing: 6) {
                StatusGlyph(kind: self.kind, size: self.skin.row.glyphSize)
                VStack(alignment: .leading, spacing: 2) {
                    Text(self.readiness.headline)
                        .font(.system(size: self.skin.row.nameSize, weight: .semibold))
                        .foregroundStyle(self.readiness.kind == .ready ? self.skin.ok.text : self.skin.text)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(self.readiness.reasons.dropFirst().enumerated()), id: \.offset) { _, reason in
                        Text(reason)
                            .font(.system(size: self.skin.row.detailSize + 1))
                            .foregroundStyle(self.skin.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if self.model.isWatching {
                        Text("Checking every 15 seconds")
                            .font(.system(size: self.skin.row.detailSize))
                            .foregroundStyle(self.skin.tertiaryText)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, self.skin.row.itemPadding)
            .padding(.bottom, 2)
            .accessibilityElement(children: .combine)
        }
    }

    private var kind: StatusGlyph.Kind {
        switch self.readiness.kind {
        case .ready, .finished: .pass
        case .waiting: .pending
        case .blocked: self.readiness.reasons.first == "Branch is behind base" ? .behind : .fail
        }
    }
}

private struct PullChecksSection: View {
    let checks: [PullCheck]
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionTitle(text: "Checks")
            ForEach(Array(self.checks.enumerated()), id: \.offset) { _, check in
                HStack(spacing: 6) {
                    StatusGlyph(kind: Self.glyph(check.state), size: 12)
                    Text(check.name)
                        .foregroundStyle(self.skin.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Text(Self.label(check))
                        .foregroundStyle(self.skin.secondaryText)
                }
                .font(.system(size: self.skin.row.detailSize + 1))
                .padding(.horizontal, self.skin.row.itemPadding)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private static func glyph(_ state: PullCheckState) -> StatusGlyph.Kind {
        switch state {
        case .passed: .pass
        case .failed: .fail
        case .pending, .expected: .pending
        }
    }

    private static func label(_ check: PullCheck) -> String {
        let state = switch check.state {
        case .passed: "passed"
        case .failed: "failing"
        case .pending: "running"
        case .expected: "expected"
        }
        return check.isRequired ? "\(state) · required" : state
    }
}

// MARK: - Conversations

private struct PullThreadsSection: View {
    let model: PullDetailModel
    let threads: [PullReviewThread]
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle(text: "Conversations to resolve · \(self.threads.count)")
            ForEach(Array(self.threads.enumerated()), id: \.element.id) { index, thread in
                if index > 0 { Rectangle().fill(self.skin.separator.opacity(0.5)).frame(height: 1).padding(.horizontal, self.skin.row.itemPadding) }
                self.row(thread)
            }
        }
    }

    private func row(_ thread: PullReviewThread) -> some View {
        let action = PullDetailModel.Action.resolve(threadID: thread.id)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(Self.location(thread))
                    .font(.system(size: self.skin.row.detailSize, weight: .semibold))
                    .foregroundStyle(self.skin.text)
                    .lineLimit(1)
                    .truncationMode(.head)
                if thread.isOutdated {
                    Text("outdated").font(.system(size: self.skin.row.detailSize)).foregroundStyle(self.skin.tertiaryText)
                }
            }
            if let author = thread.authorLogin {
                Text("@\(author)")
                    .font(.system(size: self.skin.row.detailSize))
                    .foregroundStyle(self.skin.secondaryText)
            }
            Text(thread.excerpt)
                .font(.system(size: self.skin.row.detailSize + 1))
                .foregroundStyle(self.skin.secondaryText)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            self.controls(thread, action: action)
        }
        .padding(.horizontal, self.skin.row.itemPadding)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func controls(_ thread: PullReviewThread, action: PullDetailModel.Action) -> some View {
        if self.model.running == action {
            PullBusy(text: "Resolving…")
        } else if self.model.confirming == action {
            HStack(spacing: 8) {
                Text("Mark as resolved?")
                    .font(.system(size: self.skin.row.detailSize + 1))
                    .foregroundStyle(self.skin.text)
                Button("Resolve") { self.model.perform(action) }
                    .buttonStyle(PanelPrimaryButtonStyle())
                    .accessibilityLabel("Confirm: mark conversation as resolved")
                PullTextButton(title: "Cancel", spoken: "Cancel resolving") { self.model.cancelConfirm() }
            }
        } else {
            HStack(spacing: 12) {
                if thread.viewerCanResolve {
                    PullTextButton(
                        title: "Resolve…", spoken: "Resolve conversation on \(Self.location(thread))",
                        hint: "Asks you to confirm first"
                    ) { self.model.beginConfirm(action) }
                        .disabled(self.model.running != nil)
                }
                if let url = thread.url {
                    PullTextButton(title: "Open on GitHub", spoken: "Open conversation on GitHub") { NSWorkspace.shared.open(url) }
                }
            }
        }
    }

    private static func location(_ thread: PullReviewThread) -> String {
        guard let path = thread.path else { return "General" }
        return thread.line.map { "\(path):\($0)" } ?? path
    }
}

// MARK: - Actions

private struct PullActionsSection: View {
    let model: PullDetailModel
    let detail: PullRequestDetail
    let readiness: PullReadiness
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: "Finish")
            if self.readiness.canUpdateBranch { self.updateBranch }
            self.merge
            if let error = self.model.actionError {
                self.message(error, color: MenuInk.status(.fail))
            } else if let notice = self.model.notice {
                self.message(notice, color: self.skin.secondaryText)
            }
        }
    }

    @ViewBuilder
    private var updateBranch: some View {
        let action = PullDetailModel.Action.updateBranch
        if self.model.running == action {
            PullBusy(text: "Updating branch…").padding(.horizontal, self.skin.row.itemPadding)
        } else if self.model.confirming == action {
            VStack(alignment: .leading, spacing: 4) {
                Text("Merge \(self.detail.baseRef) into \(self.detail.headRef)? GitHub makes and signs the commit.")
                    .font(.system(size: self.skin.row.nameSize))
                    .foregroundStyle(self.skin.text)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Update branch") { self.model.perform(action) }
                        .buttonStyle(PanelPrimaryButtonStyle())
                        .accessibilityLabel("Confirm: update branch")
                    PullTextButton(title: "Cancel", spoken: "Cancel updating branch") { self.model.cancelConfirm() }
                }
            }
            .padding(.horizontal, self.skin.row.itemPadding)
        } else {
            Button("Update branch…") { self.model.beginConfirm(action) }
                .accessibilityLabel("Update branch")
                .accessibilityHint("Asks you to confirm first")
                .buttonStyle(PanelPrimaryButtonStyle())
                .disabled(self.model.running != nil)
                .padding(.horizontal, self.skin.row.itemPadding)
        }
    }

    @ViewBuilder
    private var merge: some View {
        let action = PullDetailModel.Action.merge
        let methods = self.detail.allowedMergeMethods
        VStack(alignment: .leading, spacing: 5) {
            if methods.count > 1 {
                PanelSegmented(options: methods, label: \.shortLabel, selection: Binding(
                    get: { self.model.mergeMethod }, set: { self.model.mergeMethod = $0 }
                ))
                .accessibilityLabel("Merge method")
            } else if let only = methods.first {
                Text(only.label).font(.system(size: self.skin.row.detailSize + 1)).foregroundStyle(self.skin.secondaryText)
            }
            Toggle(isOn: Binding(get: { self.model.deleteBranchAfterMerge }, set: { self.model.deleteBranchAfterMerge = $0 })) {
                Text("Delete branch after merge")
                    .font(.system(size: self.skin.row.detailSize + 1))
                    .foregroundStyle(self.skin.text)
            }
            .toggleStyle(.checkbox)
            .disabled(
                self.detail.isCrossRepository || self.detail.headRefID == nil
                    || self.model.confirming != nil || self.model.running != nil
            )
            if self.model.running == action {
                PullBusy(text: "Merging…")
            } else if self.model.confirming == action {
                Text(self.detail.mergeConfirmation(
                    method: self.model.mergeMethod, deleteBranch: self.model.deleteBranchAfterMerge
                ))
                    .font(.system(size: self.skin.row.nameSize))
                    .foregroundStyle(self.skin.text)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Merge") { self.model.perform(action) }
                        .buttonStyle(PanelPrimaryButtonStyle())
                        .accessibilityLabel("Confirm: merge pull request")
                    PullTextButton(title: "Cancel", spoken: "Cancel merge") { self.model.cancelConfirm() }
                }
            } else {
                HStack(spacing: 8) {
                    Button("Merge…") { self.model.beginConfirm(action) }
                        .accessibilityLabel("Merge pull request")
                        .accessibilityHint("Asks you to confirm first")
                        .buttonStyle(PanelPrimaryButtonStyle())
                        .disabled(!self.model.canMerge)
                    if let reason = self.model.mergeBlockedReason {
                        Text(reason)
                            .font(.system(size: self.skin.row.detailSize + 1))
                            .foregroundStyle(self.skin.secondaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.horizontal, self.skin.row.itemPadding)
    }

    private func message(_ text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(text)
                .font(.system(size: self.skin.row.detailSize + 1))
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 4)
            PullTextButton(title: "Dismiss", spoken: "Dismiss message") { self.model.dismissMessage() }
        }
        .padding(.horizontal, self.skin.row.itemPadding)
    }
}

private extension PullMergeMethod {
    var shortLabel: String {
        switch self {
        case .squash: "Squash"
        case .merge: "Merge"
        case .rebase: "Rebase"
        }
    }
}

// MARK: - Small bits

private struct PullBusy: View {
    let text: String
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 14, height: 14)
                .accessibilityHidden(true)
            Text(self.text)
                .font(.system(size: self.skin.row.detailSize + 1))
                .foregroundStyle(self.skin.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PullTextButton: View {
    let title: String
    var spoken: String?
    var hint: String?
    let action: () -> Void
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        Button(self.title, action: self.action)
            .buttonStyle(.plain)
            .font(.system(size: self.skin.row.detailSize + 1))
            .foregroundStyle(self.skin.accent)
            .accessibilityLabel(self.spoken ?? self.title.replacingOccurrences(of: "…", with: ""))
            .accessibilityHint(self.hint ?? "")
    }
}

private struct PullMessage: View {
    let text: String
    let color: Color
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        Text(self.text)
            .font(.system(size: self.skin.row.detailSize + 1))
            .foregroundStyle(self.color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, self.skin.row.itemPadding)
            .padding(.vertical, 4)
    }
}

private struct PullLinkLine: View {
    let title: String
    let symbol: String
    @Environment(\.menuItemHighlighted) private var isHighlighted
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: self.symbol)
                .font(.system(size: 11))
                .frame(width: 16)
                .foregroundStyle(self.isHighlighted ? self.skin.selectionText : self.skin.secondaryText)
                .accessibilityHidden(true)
            Text(self.title).foregroundStyle(self.isHighlighted ? self.skin.selectionText : self.skin.text)
            Spacer()
        }
        .font(.system(size: self.skin.row.nameSize))
        .padding(.horizontal, self.skin.row.itemPadding)
        .frame(height: self.skin.itemHeight + 2)
    }
}
