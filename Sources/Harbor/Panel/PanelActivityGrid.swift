import HarborCore
import SwiftUI

/// The All range: one row per year (newest on top), twelve month columns, each cell shaded
/// on the same scale and colours as the heatmap. A year label starts each row.
extension PanelActivitySection {
    private static let rowHeight: CGFloat = 8
    private static let rowGap: CGFloat = 1.5

    func monthGrid(_ months: [MonthBucket]) -> some View {
        let levels = ActivityBuckets.levels(counts: months.map(\.count))
        // Quiet years (zero contributions) get no row; a one-line note counts them instead,
        // so thirteen mostly empty rows don't push the strip off the screen.
        let allYears = Set(months.map(\.year))
        let activeYears = Set(months.filter { $0.count > 0 }.map(\.year))
        let years = activeYears.sorted(by: >)
        let quietCount = allYears.count - activeYears.count
        let labelWidth: CGFloat = 30
        return VStack(alignment: .leading, spacing: Self.rowGap) {
            HStack(spacing: 0) {
                Color.clear.frame(width: labelWidth, height: 1)
                ForEach(Array("JFMAMJJASOND".enumerated()), id: \.offset) { _, letter in
                    Text(String(letter))
                        .font(.system(size: min(self.skin.row.detailSize - 4, 8)))
                        .foregroundStyle(self.skin.tertiaryText)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            ForEach(years, id: \.self) { year in
                HStack(spacing: 0) {
                    Text(String(year))
                        .font(.system(size: min(self.skin.row.detailSize - 3, 9)))
                        .monospacedDigit()
                        .foregroundStyle(self.skin.secondaryText)
                        .frame(width: labelWidth, alignment: .leading)
                    ForEach(1 ... 12, id: \.self) { month in
                        self.monthCell(months, levels, year: year, month: month)
                    }
                }
                .frame(height: Self.rowHeight)
            }
            if quietCount > 0 {
                Text(quietCount == 1 ? "+1 quiet year" : "+\(quietCount) quiet years")
                    .font(.system(size: min(self.skin.row.detailSize - 3, 9)))
                    .foregroundStyle(self.skin.tertiaryText)
                    .padding(.top, 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Contributions by month, \(years.count) years")
    }

    @ViewBuilder
    private func monthCell(_ months: [MonthBucket], _ levels: [Int], year: Int, month: Int) -> some View {
        if let index = months.firstIndex(where: { $0.year == year && $0.month == month }), !months[index].isFuture {
            self.cell(level: levels[index], isHovered: self.hoveredMonth == index, glow: nil)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside {
                        self.hoveredMonth = index
                    } else if self.hoveredMonth == index {
                        self.hoveredMonth = nil
                    }
                }
        } else {
            Color.clear.frame(maxWidth: .infinity)
        }
    }
}
