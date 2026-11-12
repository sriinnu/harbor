import HarborCore
import Network
import Observation
import SwiftUI

// The panel's playful touches. Every motion here checks `accessibilityReduceMotion`, and
// everything lives only as long as the open panel (the panel's views are rebuilt on each
// open and dropped on close), so nothing animates while it is closed.

/// A one-time burst of sparkles and confetti, drawn from a few SF Symbols and dots.
struct SparkleBurst: View {
    let colors: [Color]
    @State private var progress: CGFloat = 0
    private static let count = 14

    var body: some View {
        ZStack {
            ForEach(0 ..< Self.count, id: \.self) { index in
                let angle = Double(index) / Double(Self.count) * 2 * .pi
                let reach = CGFloat(18 + (index % 3) * 9)
                let color = self.colors[index % max(self.colors.count, 1)]
                Group {
                    if index.isMultiple(of: 2) {
                        Image(systemName: "sparkle").font(.system(size: 8, weight: .bold))
                    } else {
                        Circle().frame(width: 3.5, height: 3.5)
                    }
                }
                .foregroundStyle(color)
                .scaleEffect(1.2 - 0.5 * self.progress)
                .offset(x: cos(angle) * reach * self.progress, y: sin(angle) * reach * self.progress)
                .opacity(1 - self.progress)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { withAnimation(.easeOut(duration: 1.0)) { self.progress = 1 } }
    }
}

/// "🔥 12-day" (the streak), and "best: 30" while hovered. A new best plays a short burst once.
struct StreakBadge: View {
    let streak: ContributionStreak
    /// The best streak ever, from the calendar and what was remembered.
    let best: Int
    var celebrating = false
    @Environment(\.harborPanelSkin) private var skin
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        let flame = MenuInk.status(.pending)
        let shape = Capsule()
        HStack(spacing: 3) {
            Image(systemName: "flame.fill")
                .font(.system(size: self.skin.row.detailSize - 1, weight: .bold))
                .foregroundStyle(flame)
            Text(self.label)
                .font(.system(size: self.skin.row.detailSize, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(self.skin.text)
                .contentTransition(.numericText())
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 1.5)
        .background(shape.fill(flame.opacity(0.16)))
        .overlay {
            if let edge = self.skin.segmentEdge { shape.strokeBorder(edge.color, lineWidth: edge.width) }
        }
        .overlay { if self.celebrating, !self.reduceMotion { SparkleBurst(colors: self.sparkleColors) } }
        .animation(self.reduceMotion ? nil : .snappy(duration: 0.2), value: self.hovering)
        .animation(self.reduceMotion ? nil : .snappy, value: self.streak.current)
        .onHover { self.hovering = $0 }
        .help("\(self.streak.current)-day streak · best: \(self.best)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(self.streak.current)-day streak. Best \(self.best).")
    }

    private var label: String {
        self.hovering ? "best: \(self.best)" : "\(self.streak.current)-day"
    }

    private var sparkleColors: [Color] {
        [MenuInk.status(.pending), self.skin.accent, MenuInk.status(.pass), MenuInk.status(.review)]
    }
}

/// Today's cell: a soft accent glow that pulses once there are contributions, and deepens
/// as the count grows. Still (but lit) when Reduce Motion is on.
struct TodayGlow: ViewModifier {
    /// 0 to 1: how busy today is.
    let strength: Double
    let radius: CGFloat
    @Environment(\.harborPanelSkin) private var skin
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var high = false

    /// Today's count as a 0...1 glow depth: one commit is a gentle glow, a dozen is full.
    static func strength(forCount count: Int) -> Double {
        guard count > 0 else { return 0 }
        return min(1, 0.3 + 0.7 * log2(Double(count) + 1) / log2(13))
    }

    func body(content: Content) -> some View {
        let phase = self.reduceMotion || self.high ? 1.0 : 0.55
        let shape = RoundedRectangle(cornerRadius: self.radius)
        content
            .overlay { shape.fill(self.skin.accent.opacity((0.10 + 0.30 * self.strength) * phase)) }
            .shadow(color: self.skin.accent.opacity((0.30 + 0.45 * self.strength) * phase), radius: (2 + 4 * self.strength) * phase)
            .onAppear {
                guard !self.reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { self.high = true }
            }
    }
}

/// A repo's glyph bounces once when its build goes from failing to passing.
struct CIRecoveryBounce: ViewModifier {
    let status: CIStatus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1

    static func isRecovery(from old: CIStatus, to new: CIStatus) -> Bool {
        old == .failing && new == .passing
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(self.scale)
            .onChange(of: self.status) { old, new in
                guard Self.isRecovery(from: old, to: new), !self.reduceMotion else { return }
                withAnimation(.spring(duration: 0.28, bounce: 0.5)) {
                    self.scale = 1.5
                } completion: {
                    withAnimation(.spring(duration: 0.4, bounce: 0.55)) { self.scale = 1 }
                }
            }
    }
}

extension View {
    func ciRecoveryBounce(_ status: CIStatus) -> some View {
        self.modifier(CIRecoveryBounce(status: status))
    }
}

/// Online or offline, from the system's network path. Started and stopped by the view that
/// shows it, so it listens only while the panel is open.
@MainActor
@Observable
final class NetworkMonitor {
    private(set) var isOnline = true
    @ObservationIgnored private var monitor: NWPathMonitor?

    func start() {
        guard self.monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
        self.monitor = monitor
    }

    func stop() {
        self.monitor?.cancel()
        self.monitor = nil
    }
}

/// The status bar's dot: green, amber or grey, and pulsing while a refresh runs.
struct LiveDot: View {
    let dot: PanelLiveStatus.Dot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        let refreshing = self.dot == .refreshing
        Circle()
            .fill(self.color)
            .frame(width: 7, height: 7)
            .scaleEffect(refreshing && self.pulse ? 1.35 : 1)
            .opacity(refreshing && self.pulse ? 0.45 : 1)
            .onAppear { self.update(refreshing) }
            .onChange(of: refreshing) { _, now in self.update(now) }
            .accessibilityHidden(true)
    }

    private func update(_ refreshing: Bool) {
        guard !self.reduceMotion else { return }
        if refreshing {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { self.pulse = true }
        } else {
            withAnimation(.easeOut(duration: 0.15)) { self.pulse = false }
        }
    }

    private var color: Color {
        switch self.dot {
        case .live, .refreshing: MenuInk.status(.pass)
        case .amber: MenuInk.status(.pending)
        case .offline: MenuInk.status(.none)
        }
    }
}

/// "Live · updated 12s ago · next in 4m", with the API budget on the right. The clock is a
/// `TimelineView`, which exists only while the panel is open.
struct PanelStatusBar: View {
    let lastRefresh: Date?
    let isRefreshing: Bool
    let interval: TimeInterval
    let isRateLimited: Bool
    let hasError: Bool
    let loadRateLimit: () async -> RateLimitSnapshot?
    @Environment(\.harborPanelSkin) private var skin
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var network = NetworkMonitor()
    @State private var rate: RateLimitSnapshot?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let reading = PanelLiveStatus.reading(now: context.date, PanelLiveStatus.Facts(
                lastRefresh: self.lastRefresh, isRefreshing: self.isRefreshing, interval: self.interval,
                isOnline: self.network.isOnline, isRateLimited: self.isRateLimited || self.rate?.remaining == 0,
                hasError: self.hasError
            ))
            HStack(spacing: 6) {
                LiveDot(dot: reading.dot)
                Text(reading.text)
                    .foregroundStyle(self.skin.secondaryText)
                    .contentTransition(.numericText())
                    .animation(self.reduceMotion ? nil : .snappy, value: reading.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                if let limit = PanelLiveStatus.rateLimitText(remaining: self.rate?.remaining, reset: self.rate?.reset, now: context.date) {
                    Text(limit)
                        .font(.system(size: max(self.skin.row.detailSize - 2, 8)))
                        .foregroundStyle(self.skin.tertiaryText)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .font(.system(size: self.skin.row.detailSize - 0.5))
        .monospacedDigit()
        .padding(.horizontal, self.skin.row.itemPadding)
        .padding(.vertical, 3)
        .onAppear { self.network.start() }
        .onDisappear { self.network.stop() }
        .task(id: self.lastRefresh) { self.rate = await self.loadRateLimit() }
    }
}

/// Shown in place of "Needs you" when nothing is waiting.
struct PanelAllClear: View {
    let repoCount: Int
    @Environment(\.harborPanelSkin) private var skin

    /// What was checked, not "green": a repo with no CI, or whose alerts Harbor can't see, isn't proven healthy.
    static func summary(repoCount: Int) -> String {
        "No failing CI or visible alerts in \(repoCount) \(repoCount == 1 ? "repo" : "repos")"
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("All clear ⚓")
                .font(.system(size: self.skin.row.nameSize, weight: .semibold))
                .foregroundStyle(self.skin.ok.text)
            Spacer(minLength: 4)
            Text(Self.summary(repoCount: self.repoCount))
                .font(.system(size: self.skin.row.detailSize))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(self.skin.secondaryText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: self.skin.noticeRadius, style: .continuous).fill(self.skin.ok.fill))
        .overlay {
            if let edge = self.skin.ok.edge {
                RoundedRectangle(cornerRadius: self.skin.noticeRadius, style: .continuous)
                    .strokeBorder(edge.color, lineWidth: edge.width)
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Shown in place of "All clear" while repos are still waiting for their first answer, so a
/// list that has not loaded never reads as calm.
struct PanelCheckingNote: View {
    let repoCount: Int
    @Environment(\.harborPanelSkin) private var skin

    /// With no repo waiting, it is the first review-request search the panel is still waiting on.
    static func text(repoCount: Int) -> String {
        repoCount == 0 ? "Checking your review requests…" : "Checking \(repoCount) \(repoCount == 1 ? "repo" : "repos")…"
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(Self.text(repoCount: self.repoCount))
                .font(.system(size: self.skin.row.detailSize))
                .monospacedDigit()
                .foregroundStyle(self.skin.secondaryText)
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
