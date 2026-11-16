import AppKit
import HarborCore
import SwiftUI

// The menu's rows as the six theme designs draw them: one header row, a "Needs you"
// section, two-line repo rows and a 26-week activity strip.

@MainActor
enum MenuInk {
    static func color(_ pick: (HarborMenuInk) -> HarborThemeColor, system: NSColor) -> Color {
        ActiveTheme.ink.map { pick($0).color } ?? Color(nsColor: system)
    }

    static var section: Color { self.color(\.section, system: .secondaryLabelColor) }

    static func status(_ kind: StatusGlyph.Kind) -> Color {
        switch kind {
        case .pass: self.color(\.pass, system: .systemGreen)
        case .fail: self.color(\.fail, system: .systemRed)
        case .pending: self.color(\.pending, system: .systemOrange)
        case .none: self.color(\.none, system: .tertiaryLabelColor)
        case .review: self.color(\.review, system: .controlAccentColor)
        case .behind: self.color(\.behind, system: .systemIndigo)
        }
    }

    /// The mark drawn inside a filled glyph: the menu's own background, so it reads as a cut-out.
    static var glyphMark: Color {
        ActiveTheme.palette?.background.color ?? Color(nsColor: .windowBackgroundColor)
    }
}

/// Status never relies on color alone: every kind also has its own shape.
struct StatusGlyph: View {
    enum Kind: Equatable {
        case pass, fail, pending, none, review, behind

        init(_ status: CIStatus) {
            switch status {
            case .passing: self = .pass
            case .failing: self = .fail
            case .pending: self = .pending
            case .unknown: self = .none
            }
        }

        var symbol: String? {
            switch self {
            case .pass: "checkmark"
            case .fail: "xmark"
            case .pending: "clock"
            case .behind: "arrow.down"
            case .review: "eye"
            case .none: nil
            }
        }

        /// The state as text. The glyph is hidden from VoiceOver, so rows read this instead; the
        /// hollow dashed ring ("not checked") is a state too, not an absence of one.
        var spokenState: String {
            switch self {
            case .pass: "passing"
            case .fail: "failing"
            case .pending: "pending"
            case .none: "not checked"
            case .review: "review requested"
            case .behind: "behind upstream"
            }
        }
    }

    let kind: Kind
    var size: CGFloat = 14
    @Environment(\.menuItemHighlighted) private var isHighlighted
    @Environment(\.menuRowStyle) private var rowStyle

    var body: some View {
        ZStack {
            if let symbol = self.kind.symbol {
                Circle().fill(self.fill)
                if let edge = self.rowStyle.glyphEdge, !self.isHighlighted {
                    Circle().strokeBorder(edge, lineWidth: self.rowStyle.glyphEdgeWidth)
                }
                Image(systemName: symbol)
                    .font(.system(size: self.size * 0.56, weight: .heavy))
                    .foregroundStyle(self.isHighlighted ? MenuHighlightStyle.selectionBackground(true) : MenuInk.glyphMark)
            } else {
                Circle()
                    .strokeBorder(self.fill, style: StrokeStyle(lineWidth: 1.4, dash: [2.4, 2.2]))
            }
        }
        .frame(width: self.size, height: self.size)
        .accessibilityHidden(true)
    }

    private var fill: Color {
        self.isHighlighted ? MenuHighlightStyle.selectionText : MenuInk.status(self.kind)
    }
}

/// "NEEDS YOU · 3", styled per theme.
struct MenuSectionHeader: View {
    let title: String
    @Environment(\.menuRowStyle) private var rowStyle

    var body: some View {
        let style = ActiveTheme.theme.sectionStyle
        Text(style.uppercase ? self.title.uppercased() : self.title)
            .font(.system(size: self.rowStyle.sectionSize, weight: style.bold ? .bold : .semibold))
            .tracking(style.tracking)
            .foregroundStyle(MenuInk.section)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, self.rowStyle.itemPadding)
            .padding(.top, self.rowStyle.sectionTopPadding)
            .padding(.bottom, self.rowStyle.sectionBottomPadding)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Who you are, which providers are connected, how fresh the data is, and refresh.
/// One signed-in GitHub account in the account switcher.
struct AccountChoice: Identifiable, Equatable {
    let id: String
    let login: String
    let host: String
    let isActive: Bool
}

struct MenuAccountHeader: View {
    let login: String
    let providers: [ProviderType]
    let lastRefresh: Date?
    let isRefreshing: Bool
    let onRefresh: () -> Void
    /// Every signed-in GitHub account; with more than one, the name opens a switcher.
    var accounts: [AccountChoice] = []
    var onSwitch: (String) -> Void = { _ in }
    @Environment(\.menuRowStyle) private var rowStyle

    var body: some View {
        HStack(spacing: 8) {
            self.avatar
            self.name
            HStack(spacing: 4) {
                ForEach(self.providers, id: \.self) { provider in
                    Circle()
                        .fill(Self.providerColor(provider))
                        .frame(width: 8, height: 8)
                        .help(provider.displayName)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Connected: \(self.providers.map(\.displayName).joined(separator: ", "))")
            Spacer(minLength: 8)
            Text(self.freshness)
                .font(.system(size: self.rowStyle.detailSize))
                .monospacedDigit()
                .foregroundStyle(MenuHighlightStyle.normalSecondaryText)
            Button(action: self.onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .rotationEffect(.degrees(self.isRefreshing ? 180 : 0))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(MenuHighlightStyle.normalSecondaryText)
            .disabled(self.isRefreshing)
            .help("Refresh now")
            .accessibilityLabel("Refresh now")
        }
        .padding(.leading, self.rowStyle.itemPadding)
        .padding(.trailing, 2)
        .padding(.vertical, 4)
        .frame(minHeight: self.rowStyle.headHeight)
    }

    @ViewBuilder
    private var name: some View {
        let label = Text(self.login)
            .font(.system(size: self.rowStyle.nameSize, weight: .semibold))
            .foregroundStyle(MenuHighlightStyle.normalPrimaryText)
            .lineLimit(1)
        if self.accounts.count > 1 {
            Menu {
                ForEach(self.accounts) { account in
                    Button {
                        self.onSwitch(account.id)
                    } label: {
                        Text(verbatim: account.isActive ? "\(account.login) (active)" : account.login)
                    }
                    .disabled(account.isActive)
                }
            } label: {
                label
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .fixedSize()
            .help("Switch GitHub account")
            .accessibilityLabel("Switch GitHub account, now \(self.login)")
        } else {
            label
        }
    }

    private var avatar: some View {
        let ink = ActiveTheme.ink
        return Text(String(self.login.prefix(1)).uppercased())
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(ink?.avatarText.color ?? .white)
            .frame(width: 24, height: 24)
            .background(Circle().fill(ink?.avatarFill.color ?? Color.accentColor))
            .overlay {
                if let ring = ink?.avatarBorder {
                    Circle().strokeBorder(ring.color, lineWidth: 1.5)
                }
            }
            .accessibilityHidden(true)
    }

    private var freshness: String {
        if self.isRefreshing { return "Refreshing…" }
        guard let lastRefresh else { return "" }
        if Date().timeIntervalSince(lastRefresh) < 60 { return "Just now" }
        return RelativeFormatter.string(from: lastRefresh, relativeTo: Date())
    }

    private static func providerColor(_ provider: ProviderType) -> Color {
        switch provider {
        case .github: MenuHighlightStyle.normalPrimaryText
        case .azureDevOps: Color(red: 0.30, green: 0.64, blue: 1)
        case .gitlab: Color(red: 0.91, green: 0.45, blue: 0.21)
        }
    }
}

/// One thing waiting on you: a failing build, open security alerts.
struct NeedsYouRow: View {
    let kind: StatusGlyph.Kind
    let title: String
    let detail: String
    let age: String?
    @Environment(\.menuItemHighlighted) private var isHighlighted
    @Environment(\.menuRowStyle) private var rowStyle

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            self.mark
                .frame(width: self.rowStyle.glyphBox, height: self.rowStyle.glyphBox)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline) {
                    Text(self.title)
                        .font(.system(size: self.rowStyle.nameSize, weight: .semibold))
                        .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let age {
                        Text(age)
                            .font(.system(size: self.rowStyle.detailSize))
                            .monospacedDigit()
                            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    }
                }
                Text(self.detail)
                    .font(.system(size: self.rowStyle.detailSize))
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, self.rowStyle.itemPadding)
        .padding(.vertical, 4)
        .frame(minHeight: self.rowStyle.rowHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spokenLabel(kind: self.kind, title: self.title, detail: self.detail, age: self.age))
    }

    /// "Review requested: owner/repo, title, 2 days" (the glyph names the state, then the text).
    static func spokenLabel(kind: StatusGlyph.Kind, title: String, detail: String, age: String?) -> String {
        ["\(kind.spokenState): \(title)", detail, age].compactMap(\.self).filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// The signal-flag theme draws CI problems as flags, like the repo list does.
    @ViewBuilder
    private var mark: some View {
        switch self.kind {
        case .fail: CIStatusMark(status: .failing) { StatusGlyph(kind: self.kind, size: self.rowStyle.glyphSize) }
        case .pending: CIStatusMark(status: .pending) { StatusGlyph(kind: self.kind, size: self.rowStyle.glyphSize) }
        default: StatusGlyph(kind: self.kind, size: self.rowStyle.glyphSize)
        }
    }
}

/// Two lines per repo: status, name, release plate and counts; then local Git and the
/// latest event.
struct CompactRepoRow: View {
    let repo: RepositoryDisplayModel
    let isPinned: Bool
    /// Shows a small ↗ while the row is highlighted that runs this, without opening the row.
    /// Nil leaves it out (the system menu has no room for it).
    var onOpenExternally: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.menuItemHighlighted) private var isHighlighted
    @Environment(\.menuRowStyle) private var rowStyle

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            CIStatusMark(status: self.repo.ciStatus) {
                StatusGlyph(kind: StatusGlyph.Kind(self.repo.ciStatus), size: self.rowStyle.glyphSize)
            }
            .frame(width: self.rowStyle.glyphBox, height: self.rowStyle.glyphBox)
            .ciRecoveryBounce(self.repo.ciStatus)
            VStack(alignment: .leading, spacing: 1) {
                self.firstLine
                self.secondLine
            }
        }
        .padding(.horizontal, self.rowStyle.itemPadding)
        .padding(.vertical, 4)
        .frame(minHeight: self.rowStyle.rowHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spokenLabel(repo: self.repo, isPinned: self.isPinned))
        .accessibilityActions {
            if let open = self.onOpenExternally {
                Button("Open on the web", action: open)
            }
        }
    }

    /// One line per repo for VoiceOver: name, CI state (the lamp is hidden), release, counts,
    /// the local clone and the latest event.
    static func spokenLabel(repo: RepositoryDisplayModel, isPinned: Bool) -> String {
        var parts = [repo.source.name, "CI \(StatusGlyph.Kind(repo.ciStatus).spokenState)"]
        if isPinned { parts.append("pinned") }
        if let tag = repo.source.latestRelease?.tag { parts.append("release \(tag)") }
        if repo.source.pullCountsKnown {
            parts.append(repo.pulls == 1 ? "1 pull request" : "\(repo.pulls) pull requests")
            parts.append(repo.issues == 1 ? "1 issue" : "\(repo.issues) issues")
        }
        if let alerts = repo.source.security?.openAlertCount, alerts > 0 {
            parts.append(alerts == 1 ? "1 security alert" : "\(alerts) security alerts")
        }
        if let local = repo.localStatus {
            var clone = "local clone on \(local.branch)"
            if let behind = local.behindCount, behind > 0 { clone += ", \(behind) behind" }
            if let ahead = local.aheadCount, ahead > 0 { clone += ", \(ahead) ahead" }
            if !local.isClean { clone += ", uncommitted changes" }
            parts.append(clone)
        }
        if let activity = repo.activityLine {
            parts.append([activity, repo.latestActivityAge].compactMap(\.self).joined(separator: ", "))
        } else if let error = repo.error {
            parts.append("could not be checked: \(error)")
        }
        return parts.joined(separator: ", ")
    }

    private var firstLine: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(self.repo.source.name)
                .font(.system(size: self.rowStyle.nameSize, weight: .semibold))
                .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
                .lineLimit(1)
                .help(self.repo.title)
            if let tag = self.repo.source.latestRelease?.tag {
                ReleasePlate(tag: tag)
            }
            if self.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .accessibilityLabel("Pinned")
            }
            Spacer(minLength: 8)
            if let open = self.onOpenExternally {
                Button(action: open) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                .opacity(self.isHighlighted ? 1 : 0)
                .allowsHitTesting(self.isHighlighted)
                .help("Open \(self.repo.title) on the web")
                .accessibilityLabel("Open \(self.repo.title) on the web")
            }
            Text(self.counts)
                .font(.system(size: self.rowStyle.detailSize))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(self.reduceMotion ? nil : .snappy, value: self.counts)
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                .lineLimit(1)
                .layoutPriority(1)
        }
    }

    @ViewBuilder
    private var secondLine: some View {
        let parts = self.secondLineParts
        if !parts.isEmpty {
            HStack(spacing: 4) {
                if let local = self.repo.localStatus {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 9))
                    Text(local.branch).lineLimit(1).truncationMode(.middle)
                    if let behind = local.behindCount, behind > 0 {
                        Text("↓\(behind)").fontWeight(.bold)
                    }
                    if let ahead = local.aheadCount, ahead > 0 {
                        Text("↑\(ahead)").fontWeight(.bold)
                    }
                    if !local.isClean {
                        Text("· changed").foregroundStyle(self.isHighlighted ? MenuHighlightStyle.selectionText : MenuInk.status(.pending))
                    }
                    if parts.count > 1 { Text("·") }
                }
                if let event = parts.last, parts.count > 1 || self.repo.localStatus == nil {
                    Text(event).lineLimit(1).truncationMode(.tail)
                }
            }
            .font(.system(size: self.rowStyle.detailSize))
            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            .lineLimit(1)
        }
    }

    /// The branch (if local) and the latest event with its age.
    private var secondLineParts: [String] {
        var parts: [String] = []
        if let local = self.repo.localStatus { parts.append(local.branch) }
        if let activity = self.repo.activityLine {
            parts.append([activity, self.repo.latestActivityAge].compactMap(\.self).joined(separator: " · "))
        } else if let error = self.repo.error {
            parts.append(error)
        }
        return parts
    }

    private var counts: String {
        var parts: [String] = []
        if self.repo.source.pullCountsKnown {
            parts.append(self.repo.pulls == 1 ? "1 PR" : "\(self.repo.pulls) PRs")
            parts.append(self.repo.issues == 1 ? "1 issue" : "\(self.repo.issues) issues")
        }
        if let alerts = self.repo.source.security?.openAlertCount, alerts > 0 {
            parts.append(alerts == 1 ? "1 alert" : "\(alerts) alerts")
        }
        return parts.joined(separator: " · ")
    }
}

/// The brass (or ink) plate with the latest release tag.
struct ReleasePlate: View {
    let tag: String
    @Environment(\.menuItemHighlighted) private var isHighlighted
    @Environment(\.menuRowStyle) private var rowStyle

    var body: some View {
        let text = self.textColor
        let shape = RoundedRectangle(cornerRadius: self.rowStyle.tagRadius)
        Text(self.tag)
            .font(.system(size: self.rowStyle.tagSize, weight: self.rowStyle.tagWeight, design: .monospaced))
            .foregroundStyle(text)
            .lineLimit(1)
            .padding(.horizontal, self.rowStyle.tagPaddingX)
            .padding(.vertical, 0.5)
            .background(shape.fill(self.fillColor))
            .overlay(shape.strokeBorder(self.borderColor(text: text), lineWidth: 1))
            .accessibilityLabel("Release \(self.tag)")
    }

    // Split out so the body type-checks quickly on every supported compiler.
    private var textColor: Color {
        if self.isHighlighted { return MenuHighlightStyle.selectionText }
        return ActiveTheme.ink?.tagText.color ?? Color(nsColor: .secondaryLabelColor)
    }

    private var fillColor: Color {
        if self.isHighlighted { return .clear }
        guard let ink = ActiveTheme.ink else { return Color.primary.opacity(0.06) }
        return ink.tagFill?.color ?? .clear
    }

    private func borderColor(text: Color) -> Color {
        if self.isHighlighted { return text.opacity(0.4) }
        return ActiveTheme.ink?.tagBorder.color ?? Color.primary.opacity(0.1)
    }
}

/// "Your activity" and a 26-week strip; the full year opens as a submenu.
struct ActivityStripRow: View {
    let cells: [HeatmapCell]
    @Environment(\.menuItemHighlighted) private var isHighlighted
    @Environment(\.menuRowStyle) private var rowStyle

    var body: some View {
        HStack(spacing: 8) {
            Text("Your activity")
                .font(.system(size: self.rowStyle.nameSize))
                .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                ForEach(Array(Self.weeklyLevels(self.cells).enumerated()), id: \.offset) { _, level in
                    RoundedRectangle(cornerRadius: self.rowStyle.heatRadius)
                        .fill(self.color(level))
                        .overlay {
                            if let edge = self.rowStyle.heatEdge, level == 0, !self.isHighlighted {
                                RoundedRectangle(cornerRadius: self.rowStyle.heatRadius).strokeBorder(edge, lineWidth: 1)
                            }
                        }
                        .frame(width: 5, height: 10)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.horizontal, self.rowStyle.itemPadding)
        .padding(.vertical, 6)
        .frame(minHeight: 30)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your activity, last 26 weeks")
    }

    private func color(_ level: Int) -> Color {
        if let ramp = self.rowStyle.heat, !self.isHighlighted, ramp.indices.contains(level) { return ramp[level] }
        let accent = ActiveTheme.palette?.accent.color ?? Color(nsColor: .systemGreen)
        if self.isHighlighted {
            return MenuHighlightStyle.selectionText.opacity(level == 0 ? 0.25 : 0.4 + 0.15 * Double(level))
        }
        return level == 0 ? MenuHighlightStyle.normalPrimaryText.opacity(0.09) : accent.opacity(0.25 + 0.1875 * Double(level))
    }

    /// The last 26 weeks summed per week, scaled to levels 0–4 against the busiest week.
    static func weeklyLevels(_ cells: [HeatmapCell], weeks: Int = 26) -> [Int] {
        ActivityBuckets.levels(ActivityBuckets.trailing(
            ActivityMerge.perDay(ActivityMerge.github(cells)), buckets: weeks, daysPerBucket: 7, now: Date()
        ))
    }
}
