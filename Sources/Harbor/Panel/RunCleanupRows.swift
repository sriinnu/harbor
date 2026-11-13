import HarborCore
import SwiftUI

/// The "Clean up old runs…" row and, below it, whatever step the cleanup is on: scanning,
/// the inline confirm, progress, the result or the first error.
struct RunCleanupRows: View {
    let model: RunCleanupModel
    let fullName: String
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        // One stable container for the pin and the disappearance: the step inside changes with
        // the phase, and a modifier on it would fire on every change.
        VStack(spacing: 0) { self.step }
            .pinsPanelOpen(PanelPin.runCleanup, while: self.isPending)
            .pinsPanelOpen(PanelPin.runCleanupDeleting, while: self.isDeleting)
            .onDisappear { self.model.viewDisappeared() }
    }

    /// A confirm, a scan or a delete is under way: the panel stays open until it settles.
    private var isPending: Bool {
        switch self.model.phase {
        case .scanning, .confirming, .deleting: true
        default: false
        }
    }

    private var isDeleting: Bool {
        if case .deleting = self.model.phase { return true }
        return false
    }

    @ViewBuilder
    private var step: some View {
        switch self.model.phase {
        case .idle:
            self.startRow
        case .scanning:
            self.status("Looking at workflow runs…", busy: true)
        case .nothingToDelete:
            self.status("Nothing to clean up. Every workflow is within its newest 5 runs.", dismiss: "OK")
        case let .confirming(plan):
            self.confirm(plan)
        case let .deleting(done, total):
            self.progress(done: done, total: total)
        case let .finished(deleted):
            self.status("Deleted \(deleted) old run\(deleted == 1 ? "" : "s").", dismiss: "OK")
        case let .stopped(deleted):
            self.status("Stopped. Deleted \(deleted) old run\(deleted == 1 ? "" : "s").", dismiss: "OK")
        case let .rateLimited(message):
            self.status(message, color: MenuInk.status(.fail), dismiss: "OK")
        case let .failed(deleted, message):
            self.status(
                deleted > 0 ? "\(message). Stopped after \(deleted) deleted." : message,
                color: MenuInk.status(.fail), dismiss: "OK"
            )
        }
    }

    private var startRow: some View {
        PanelRow(id: "health:cleanup", action: { self.model.scan(fullName: self.fullName) }) {
            CleanupLine(title: "Clean up old runs…", symbol: "trash")
        }
        .help(RunCleanup.help)
        .accessibilityLabel("Clean up old workflow runs")
        .accessibilityHint(RunCleanup.help)
    }

    private func confirm(_ plan: RunCleanup.Plan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(RunCleanup.confirmation(plan: plan))
                .font(.system(size: self.skin.row.nameSize))
                .foregroundStyle(self.skin.text)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Delete") { self.model.confirm(fullName: self.fullName) }
                    .buttonStyle(PanelPrimaryButtonStyle())
                    .accessibilityLabel("Delete old workflow runs")
                    .accessibilityHint("Permanently deletes the runs listed above")
                Button("Cancel") { self.model.dismiss() }
                    .accessibilityLabel("Cancel cleanup")
                    .buttonStyle(.plain)
                    .font(.system(size: self.skin.row.nameSize))
                    .foregroundStyle(self.skin.accent)
            }
        }
        .padding(.horizontal, self.skin.row.itemPadding)
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    private func progress(done: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Deleting \(done) of \(total)…")
                    .monospacedDigit()
                    .font(.system(size: self.skin.row.nameSize))
                    .foregroundStyle(self.skin.text)
                Spacer(minLength: 4)
                Button(self.model.isStopping ? "Stopping…" : "Stop") { self.model.stop() }
                    .disabled(self.model.isStopping)
                    .accessibilityHint("Stops after the run being deleted now")
                    .buttonStyle(.plain)
                    .font(.system(size: self.skin.row.detailSize))
                    .foregroundStyle(self.skin.accent)
            }
            ProgressView(value: Double(done), total: Double(max(total, 1)))
                .progressViewStyle(.linear)
                .tint(self.skin.accent)
                .accessibilityLabel("Deleting old runs")
                .accessibilityValue("\(done) of \(total)")
        }
        .padding(.horizontal, self.skin.row.itemPadding)
        .padding(.vertical, 4)
    }

    private func status(_ text: String, busy: Bool = false, color: Color? = nil, dismiss: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if busy { ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 14, height: 14).accessibilityHidden(true) }
            Text(text)
                .font(.system(size: self.skin.row.detailSize + 1))
                .foregroundStyle(color ?? self.skin.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let dismiss {
                Button(dismiss) { self.model.dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: self.skin.row.detailSize + 1))
                    .foregroundStyle(self.skin.accent)
                    .accessibilityLabel("Dismiss cleanup message")
            }
        }
        .padding(.horizontal, self.skin.row.itemPadding)
        .padding(.vertical, 4)
    }
}

private struct CleanupLine: View {
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
            Text(self.title)
                .foregroundStyle(self.isHighlighted ? self.skin.selectionText : self.skin.text)
            Spacer()
        }
        .font(.system(size: self.skin.row.nameSize))
        .padding(.horizontal, self.skin.row.itemPadding)
        .frame(height: self.skin.itemHeight)
        .accessibilityElement(children: .combine)
    }
}
