import HarborCore
import SwiftUI

/// Views and clones for the last 14 days, from the stats the repo list already loaded:
/// the totals and unique counts, and a tiny bar per day when GitHub gave them.
struct PanelTrafficSection: View {
    /// Nil when GitHub didn't share traffic (it needs push access to the repo).
    let traffic: TrafficStats?
    @Environment(\.harborPanelSkin) private var skin

    static let emptyText = "No visitors yet. GitHub keeps the last 14 days."
    static let unavailableText = "Traffic isn't available. GitHub shows it only to people with push access, and Harbor's token needs the repo scope."

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle(text: "Traffic · last 14 days")
            if let traffic {
                if traffic.isEmpty {
                    self.note(Self.emptyText)
                } else {
                    self.metric("Views", total: traffic.views, unique: traffic.uniqueVisitors, days: traffic.viewsByDay)
                    self.metric("Clones", total: traffic.clones, unique: traffic.uniqueCloners, days: traffic.clonesByDay)
                }
            } else {
                self.note(Self.unavailableText)
            }
        }
        .padding(.bottom, 2)
        .accessibilityElement(children: .contain)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: self.skin.row.detailSize))
            .foregroundStyle(self.skin.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, self.skin.row.itemPadding)
    }

    private func metric(_ title: String, total: Int?, unique: Int, days: [Int]?) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(self.skin.text)
                .frame(width: 44, alignment: .leading)
            if let days, days.contains(where: { $0 > 0 }) {
                TrafficBars(days: days)
                    .frame(maxWidth: .infinity)
            } else {
                Spacer(minLength: 0)
            }
            Text(Self.value(total: total, unique: unique))
                .monospacedDigit()
                .foregroundStyle(self.skin.secondaryText)
                .lineLimit(1)
        }
        .font(.system(size: self.skin.row.nameSize))
        .padding(.horizontal, self.skin.row.itemPadding)
        .frame(height: self.skin.itemHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(Self.value(total: total, unique: unique))")
    }

    /// "128 · 41 unique", or just "41 unique" for stats cached before totals were kept.
    static func value(total: Int?, unique: Int) -> String {
        guard let total else { return "\(unique.formatted()) unique" }
        return "\(total.formatted()) · \(unique.formatted()) unique"
    }
}

/// One bar per day, tallest day full height; a quiet day is a hairline.
private struct TrafficBars: View {
    let days: [Int]
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        let busiest = CGFloat(max(self.days.max() ?? 0, 1))
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(self.days.enumerated()), id: \.offset) { _, count in
                RoundedRectangle(cornerRadius: 1)
                    .fill(count > 0 ? self.skin.accent : self.skin.tertiaryText.opacity(0.4))
                    .frame(height: count > 0 ? max(2, 14 * CGFloat(count) / busiest) : 1)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 14, alignment: .bottom)
        .accessibilityHidden(true)
    }
}
