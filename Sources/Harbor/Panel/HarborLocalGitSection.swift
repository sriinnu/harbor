import AppKit
import HarborCore
import SwiftUI

/// "Local clone" in a repo's detail: where the clone stands, and the Git actions that fix it.
/// Everything that moves commits asks inline first; fetch and switching a branch run at once.
struct HarborLocalGitSection: View {
    let model: LocalGitModel
    /// The session's status for this clone; `model.fresh` wins until the next refresh.
    let status: LocalRepoStatus
    let openTerminal: (URL) -> Void
    @Environment(\.harborPanelSkin) private var skin

    private var shown: LocalRepoStatus { self.model.fresh ?? self.status }

    var body: some View {
        let shown = self.shown
        VStack(alignment: .leading, spacing: 0) {
            Text("Local clone")
                .font(.system(size: self.skin.row.detailSize, weight: .semibold))
                .foregroundStyle(self.skin.secondaryText)
                .padding(.horizontal, self.skin.row.itemPadding)
                .padding(.bottom, 2)
            self.summary(shown)
            LocalGitFeedback(model: self.model, status: shown)
            if self.model.confirming == nil, !self.model.isBusy {
                self.actions(shown)
                self.branchPicker(shown)
                self.openRow(shown)
            }
        }
        .pinsPanelOpen("local-git", while: self.model.needsPanelOpen)
        .onChange(of: self.status) { _, _ in self.model.sessionStatusChanged() }
    }

    private func summary(_ status: LocalRepoStatus) -> some View {
        HStack(spacing: 8) {
            Image(systemName: status.syncState.symbolName)
                .font(.system(size: 11))
                .frame(width: 16)
                .foregroundStyle(self.skin.secondaryText)
            Text(status.summaryLine)
                .font(.system(size: self.skin.row.nameSize))
                .foregroundStyle(self.skin.text)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, self.skin.row.itemPadding)
        .frame(height: self.skin.itemHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Local clone, \(status.branch), \(status.dirtyText), \(status.aheadBehindText)")
    }

    private func actions(_ status: LocalRepoStatus) -> some View {
        let hasUpstream = status.upstreamBranch != nil && status.aheadCount != nil
        return FlowLayout(itemSpacing: 12, lineSpacing: 4) {
            PanelTextButton(title: "Fetch", symbol: "arrow.down.circle") { self.model.request(.fetch) }
            PanelTextButton(
                title: "Pull", symbol: "arrow.down.to.line", isEnabled: (status.behindCount ?? 0) > 0, confirms: true
            ) {
                self.model.request(.pullFastForward)
            }
            PanelTextButton(title: "Sync", symbol: "arrow.triangle.2.circlepath", isEnabled: hasUpstream, confirms: true) {
                self.model.request(.sync)
            }
            PanelTextButton(title: "Rebase…", symbol: "arrow.triangle.branch", isEnabled: hasUpstream) {
                self.model.request(.rebase)
            }
            PanelTextButton(title: "Reset…", symbol: "arrow.uturn.backward", isEnabled: hasUpstream, isDestructive: true) {
                self.model.request(.reset)
            }
        }
        .padding(.horizontal, self.skin.row.itemPadding)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func branchPicker(_ status: LocalRepoStatus) -> some View {
        PanelRow(id: "detail:switch", action: {
            self.model.isPickingBranch.toggle()
        }) {
            ListActionLine(
                title: self.model.isPickingBranch ? "Switch branch (choose one)" : "Switch branch…",
                symbol: "arrow.triangle.swap"
            )
        }
        if self.model.isPickingBranch {
            VStack(alignment: .leading, spacing: 0) {
                switch self.model.branches {
                case .idle, .loading:
                    SkeletonLines(count: 2)
                case let .failed(message):
                    Text(message)
                        .font(.system(size: self.skin.row.detailSize + 1))
                        .foregroundStyle(MenuInk.status(.fail))
                        .padding(.horizontal, self.skin.row.itemPadding)
                case let .loaded(names):
                    if names.isEmpty {
                        Text("No other local branches.")
                            .font(.system(size: self.skin.row.detailSize + 1))
                            .foregroundStyle(self.skin.secondaryText)
                            .padding(.horizontal, self.skin.row.itemPadding)
                    }
                    ForEach(names.prefix(12), id: \.self) { name in
                        PanelRow(id: "detail:branch:\(name)", action: { self.model.request(.switchBranch(name)) }) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.triangle.branch").font(.system(size: 10)).frame(width: 16)
                                    .accessibilityHidden(true)
                                Text(name).lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 0)
                            }
                            .font(.system(size: self.skin.row.nameSize))
                            .foregroundStyle(self.skin.text)
                            .padding(.leading, self.skin.row.itemPadding + 12)
                            .padding(.trailing, self.skin.row.itemPadding)
                            .frame(height: self.skin.itemHeight)
                        }
                        .accessibilityLabel("Switch to branch \(name)")
                        .accessibilityHint("Switches immediately")
                    }
                    if names.count > 12 {
                        Text("+\(names.count - 12) more · use Terminal")
                            .font(.system(size: self.skin.row.detailSize))
                            .foregroundStyle(self.skin.tertiaryText)
                            .padding(.horizontal, self.skin.row.itemPadding + 12)
                    }
                }
            }
            .task { await self.model.loadBranches() }
            .padding(.bottom, 2)
        }
    }

    private func openRow(_ status: LocalRepoStatus) -> some View {
        FlowLayout(itemSpacing: 12, lineSpacing: 4) {
            PanelTextButton(title: "Terminal", symbol: "terminal") { self.openTerminal(status.path) }
            PanelTextButton(title: "Finder", symbol: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([status.path])
            }
            if let editor = TowerEditor.application {
                PanelTextButton(title: editor.name, symbol: "chevron.left.forwardslash.chevron.right") {
                    NSWorkspace.shared.open(
                        [status.path], withApplicationAt: editor.url, configuration: NSWorkspace.OpenConfiguration()
                    )
                }
            }
        }
        .padding(.horizontal, self.skin.row.itemPadding)
        .padding(.vertical, 4)
    }
}

/// The confirm, the progress and the failure of a clone's command. Shared by the detail
/// pane and the "behind" Needs-you row.
struct LocalGitFeedback: View {
    let model: LocalGitModel
    let status: LocalRepoStatus
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let running = self.model.running {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 14, height: 14)
                        .accessibilityHidden(true)
                    Text(running.busyText)
                        .font(.system(size: self.skin.row.detailSize + 1))
                        .foregroundStyle(self.skin.secondaryText)
                }
                .accessibilityElement(children: .combine)
            } else if let command = self.model.confirming {
                Text(command.confirmQuestion(branch: self.status.branch, upstream: self.status.upstreamBranch))
                    .font(.system(size: self.skin.row.nameSize))
                    .foregroundStyle(command.isDestructive ? MenuInk.status(.fail) : self.skin.text)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button(command.isDestructive ? "Reset" : command.title) { self.model.confirm() }
                        .buttonStyle(PanelPrimaryButtonStyle())
                        .accessibilityLabel("Confirm \(command.isDestructive ? "reset" : command.title.lowercased())")
                    PanelTextButton(title: "Cancel") { self.model.cancel() }
                }
            }
            if let error = self.model.error {
                Text(error)
                    .font(.system(size: self.skin.row.detailSize + 1))
                    .foregroundStyle(MenuInk.status(.fail))
                    .fixedSize(horizontal: false, vertical: true)
                PanelTextButton(title: "Dismiss") { self.model.dismissError() }
            }
        }
        .padding(.horizontal, self.skin.row.itemPadding)
        .padding(.vertical, self.model.running != nil || self.model.confirming != nil || self.model.error != nil ? 4 : 0)
    }
}

/// The "N behind" Needs-you row's fix: a fast-forward, behind its own inline confirm.
struct LocalGitBehindStrip: View {
    let model: LocalGitModel
    let status: LocalRepoStatus
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LocalGitFeedback(model: self.model, status: self.status)
            if self.status.canFastForward, !self.model.isBusy, self.model.confirming == nil {
                PanelTextButton(title: "Fast-forward", symbol: "arrow.down.to.line", confirms: true) { self.model.request(.pullFastForward) }
                    .padding(.horizontal, self.skin.row.itemPadding)
                    .padding(.leading, self.skin.row.glyphBox + 8)
                    .padding(.bottom, 4)
            }
        }
        .pinsPanelOpen("local-git-need", while: self.model.needsPanelOpen)
    }
}

/// A small accent-coloured text action, optionally with a symbol.
struct PanelTextButton: View {
    let title: String
    var symbol: String?
    var isEnabled = true
    var isDestructive = false
    /// The action waits for an inline confirm; VoiceOver is told so.
    var confirms = false
    let action: () -> Void
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        Button(action: self.action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 10)).accessibilityHidden(true) }
                Text(self.title)
            }
            .font(.system(size: self.skin.row.detailSize + 1, weight: .medium))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(self.isDestructive ? MenuInk.status(.fail) : self.skin.accent)
        .opacity(self.isEnabled ? 1 : 0.35)
        .disabled(!self.isEnabled)
        .accessibilityLabel(self.title.replacingOccurrences(of: "…", with: ""))
        .accessibilityHint(self.isDestructive ? "Discards local work. Asks you to confirm first" : (self.confirms || self.title.hasSuffix("…") ? "Asks you to confirm first" : ""))
    }
}
