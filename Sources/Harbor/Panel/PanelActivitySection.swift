import HarborCore
import SwiftUI

extension ActivityRange {
    /// The segmented control's label, short so five fit beside the title; the caption below
    /// spells the range out ("last 30 days").
    var panelLabel: String {
        switch self {
        case .week: "7d"
        case .month: "30d"
        case .quarter: "3mo"
        case .year: "1y"
        case .allTime: "All"
        }
    }
}

/// What the "Your activity" section needs, gathered from the session.
struct PanelActivity: Equatable {
    var range: ActivityRange = .quarter
    var githubDays: [HeatmapCell] = []
    var githubError: String?
    var years: [ContributionYear] = []
    var yearsState: ActivityLoadState = .idle
    var others: [ProviderType: ProviderActivitySlice] = [:]
    /// One repo's own series: `githubDays` is its commit activity, All folds it by year (no
    /// per-year totals), and the strip counts commits.
    var isRepo = false
    var isLoadingRepo = false

    var words: ActivityWords { self.isRepo ? .commits : .contributions }

    var isEmpty: Bool { self.githubDays.isEmpty && self.others.isEmpty }

    /// GitHub first, then whichever other providers have been tried, in a fixed order.
    var providers: [ProviderType] {
        [.github] + [ProviderType.gitlab, .azureDevOps].filter { self.others[$0] != nil }
    }

    /// Providers that failed, with the reason.
    var unavailable: [ProviderType: String] {
        var result: [ProviderType: String] = [:]
        for (provider, slice) in self.others {
            if case let .failed(reason) = slice.state { result[provider] = reason }
        }
        if !self.isRepo, self.range == .allTime, case let .failed(reason) = self.yearsState { result[.github] = reason }
        if self.range != .allTime, self.githubDays.isEmpty, let error = self.githubError { result[.github] = error }
        return result
    }

    /// Everything the strip draws from. A failed provider contributes nothing, so a
    /// half-fetched series is never mixed in.
    var entries: [ProviderDayActivity] {
        var entries = ActivityMerge.github(self.githubDays)
        for slice in self.others.values where slice.state == .ready { entries += slice.days }
        return entries
    }

    var isLoadingLongRange: Bool {
        !self.isRepo && self.range == .allTime && self.yearsState == .loading
    }

    /// What the strip says in place of cells while something loads.
    var loadingText: String? {
        if self.isLoadingLongRange { return "Loading all time…" }
        return self.isLoadingRepo ? "Loading activity…" : nil
    }

    var partial: Set<ProviderType> {
        Set(self.others.filter { $0.value.state == .ready && $0.value.partial }.keys)
    }

    func buckets(now: Date = Date()) -> [ActivityBucket] {
        ActivityBuckets.buckets(for: self.range, entries: self.entries, years: self.years, now: now, daily: self.isRepo)
    }

    /// The All range draws a year by month grid instead of `buckets`; empty for the others.
    func months(now: Date = Date()) -> [MonthBucket] {
        guard self.range == .allTime else { return [] }
        let others = self.isRepo ? self.entries : self.entries.filter { $0.provider != .github }
        return ActivityBuckets.monthly(years: self.years, others: others, now: now)
    }
}

/// The range selector, a strip with one cell per bucket, and a caption that shows the
/// total, or the hovered cell's date, count and breakdown. Titled "Your activity" for the
/// user, and reused for one repo's commits in its detail pane.
struct PanelActivitySection: View {
    let activity: PanelActivity
    var title = "Your activity"
    let selectRange: (ActivityRange) -> Void
    /// Nil hides the profile button (a repo has none beside its strip).
    var openProfile: (() -> Void)?
    @Environment(\.harborPanelSkin) var skin
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: Int?
    @State var hoveredMonth: Int?
    @State private var storedBest = StreakStore().best
    @State private var celebrating = false

    var body: some View {
        let buckets = self.activity.buckets()
        let levels = ActivityBuckets.levels(buckets)
        let months = self.activity.months()
        let streak = self.streak
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(self.title)
                    .font(.system(size: self.skin.row.nameSize))
                    .foregroundStyle(self.skin.text)
                    .layoutPriority(1)
                if streak.current > 0 {
                    StreakBadge(streak: streak, best: max(self.storedBest, streak.best), celebrating: self.celebrating)
                }
                if let openProfile = self.openProfile {
                    Button(action: openProfile) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: self.skin.row.detailSize))
                            .foregroundStyle(self.skin.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .help("Open your profile in the browser")
                    .accessibilityLabel("Open your profile")
                }
                Spacer(minLength: 4)
                PanelSegmented(
                    options: ActivityRange.allCases,
                    label: \.panelLabel,
                    selection: Binding(get: { self.activity.range }, set: { self.choose($0) }),
                    segmentPadding: 6
                )
                .accessibilityLabel("Activity range")
            }
            if !months.isEmpty, self.activity.loadingText == nil {
                // The grid can be a dozen rows tall, so its caption sits above it where a
                // scrolled panel still shows it.
                self.caption(buckets, months: months)
                self.monthGrid(months)
            } else {
                self.strip(buckets, levels, glow: self.todayGlow(buckets))
                self.caption(buckets, months: months)
            }
        }
        .padding(.horizontal, self.skin.row.itemPadding)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
        .onChange(of: streak, initial: true) { _, now in self.record(now) }
    }

    // MARK: - Streak

    /// The current and best run across every connected provider; a repo's own strip has none.
    private var streak: ContributionStreak {
        guard !self.activity.isRepo else { return ContributionStreak(current: 0, best: 0) }
        return ContributionStreak.compute(days: ActivityMerge.perDay(self.activity.entries), now: Date())
    }

    /// Remembers a new best and, when the current streak just passed the old one, plays the
    /// celebration once (the stored best moves up at the same time, so it cannot repeat).
    private func record(_ streak: ContributionStreak) {
        guard !self.activity.isRepo else { return }
        let store = StreakStore()
        let decision = StreakCelebration.decide(stored: store.best, streak: streak)
        if decision.newBest != store.best { store.best = decision.newBest }
        self.storedBest = decision.newBest
        guard decision.celebrate, !self.reduceMotion else { return }
        self.celebrating = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.3))
            self.celebrating = false
        }
    }

    /// Which cell is today, and how busy: only for the daily calendar ranges and the weekly
    /// ones (whose last cell holds today), and only once today has contributions.
    private func todayGlow(_ buckets: [ActivityBucket]) -> (index: Int, strength: Double)? {
        guard !self.activity.isRepo, self.activity.range != .allTime, let last = buckets.last else { return nil }
        let days = ActivityMerge.perDay(self.activity.entries)
        let today = max(ActivityBuckets.calendar.startOfDay(for: Date()), days.last?.date ?? .distantPast)
        guard last.end == today, let count = days.last(where: { $0.date == today })?.total, count > 0 else { return nil }
        return (buckets.count - 1, TodayGlow.strength(forCount: count))
    }

    private func choose(_ range: ActivityRange) {
        self.hovered = nil
        self.hoveredMonth = nil
        self.selectRange(range)
    }

    // MARK: - Strip

    @ViewBuilder
    private func strip(_ buckets: [ActivityBucket], _ levels: [Int], glow: (index: Int, strength: Double)?) -> some View {
        if self.activity.loadingText != nil || buckets.isEmpty {
            HStack(spacing: 6) {
                if self.activity.loadingText != nil {
                    ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 14, height: 14)
                        .accessibilityHidden(true)
                }
                Text(self.activity.loadingText ?? "No activity yet")
                    .font(.system(size: self.skin.row.detailSize))
                    .foregroundStyle(self.skin.secondaryText)
                Spacer(minLength: 0)
            }
            .frame(height: Self.stripHeight)
        } else {
            HStack(spacing: 0) {
                ForEach(Array(buckets.enumerated()), id: \.offset) { index, _ in
                    self.cell(level: levels[index], isHovered: self.hovered == index, glow: glow?.index == index ? glow?.strength : nil)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onHover { inside in
                            if inside {
                                self.hovered = index
                            } else if self.hovered == index {
                                self.hovered = nil
                            }
                        }
                }
            }
            .frame(height: Self.stripHeight)
            .accessibilityHidden(true)
        }
    }

    private static let stripHeight: CGFloat = 16

    func cell(level: Int, isHovered: Bool, glow: Double?) -> some View {
        let radius = self.skin.row.heatRadius
        let shape = RoundedRectangle(cornerRadius: radius)
        return shape
            .fill(self.color(level))
            .modifier(OptionalTodayGlow(strength: glow, radius: radius))
            .overlay {
                if let edge = self.skin.row.heatEdge, level == 0 { shape.strokeBorder(edge, lineWidth: 1) }
            }
            .overlay {
                if isHovered { shape.strokeBorder(self.skin.text, lineWidth: 1.5) }
            }
            .padding(.horizontal, 1)
    }

    func color(_ level: Int) -> Color {
        if let ramp = self.skin.row.heat, ramp.indices.contains(level) { return ramp[level] }
        return level == 0 ? self.skin.text.opacity(0.09) : self.skin.accent.opacity(0.25 + 0.1875 * Double(level))
    }

    // MARK: - Caption

    private func caption(_ buckets: [ActivityBucket], months: [MonthBucket]) -> some View {
        let hovered = self.hovered.flatMap { buckets.indices.contains($0) ? buckets[$0] : nil }
        let month = self.hoveredMonth.flatMap { months.indices.contains($0) ? months[$0] : nil }
        let providers = self.activity.providers
        let unavailable = self.activity.unavailable
        let shares: [ProviderType: Int] = month?.providers ?? hovered?.providers
            ?? buckets.reduce(into: [:]) { $0.merge($1.providers, uniquingKeysWith: +) }
        let providerLine = ActivityBuckets.providerLine(
            shares: shares, unavailable: unavailable, connected: providers, partial: self.activity.partial
        )
        // A month has no split by kind (GitHub's per-month calendar carries none).
        let kinds: [ActivityKind: Int] = month != nil ? [:] : hovered?.kinds
            ?? buckets.reduce(into: [:]) { $0.merge($1.kinds, uniquingKeysWith: +) }
        let showsKinds = !self.activity.isRepo && (self.activity.range == .allTime || providers.count > 1)
        let size = self.skin.row.detailSize
        return VStack(alignment: .leading, spacing: 1) {
            self.line(
                month.map { ActivityBuckets.monthHoverHead($0, words: self.activity.words) }
                    ?? hovered.map { ActivityBuckets.hoverHead($0, range: self.activity.range, words: self.activity.words) }
                    ?? ActivityBuckets.totalLine(buckets, range: self.activity.range, words: self.activity.words),
                emphasized: hovered != nil || month != nil
            )
            if providers.count > 1 { self.line(providerLine ?? "", emphasized: false) }
            if showsKinds { self.line(ActivityBuckets.kindsLine(kinds) ?? "", emphasized: false) }
        }
        .font(.system(size: size))
        .monospacedDigit()
        .animation(nil, value: self.hovered)
        .animation(nil, value: self.hoveredMonth)
        .animation(self.reduceMotion ? nil : .snappy, value: ActivityBuckets.total(buckets))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func line(_ text: String, emphasized: Bool) -> some View {
        Text(text.isEmpty ? " " : text)
            .foregroundStyle(emphasized ? self.skin.text : self.skin.secondaryText)
            .contentTransition(.numericText())
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.85)
    }
}

/// Applies `TodayGlow` only to today's cell; the other cells stay plain.
private struct OptionalTodayGlow: ViewModifier {
    let strength: Double?
    let radius: CGFloat

    func body(content: Content) -> some View {
        if let strength {
            content.modifier(TodayGlow(strength: strength, radius: self.radius))
        } else {
            content
        }
    }
}
