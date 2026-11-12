import HarborCore
import SwiftUI

/// The Harbor tab: one boat per listed repository, on a shared waterline. The boat's
/// condition and the water's height are computed from what Harbor knows (`HarborBoat`);
/// the colors come from the skin. A boat opens its repo's detail.
struct HarborBoatsView: View {
    let repos: [RepositoryDisplayModel]
    let open: (RepositoryDisplayModel) -> Void
    @Environment(\.harborPanelSkin) private var skin

    private static let maxBoats = 24
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 4)

    var body: some View {
        let boats = self.repos.prefix(Self.maxBoats).map { (repo: $0, boat: HarborBoat(repo: $0, tideFromRecency: true)) }
        VStack(alignment: .leading, spacing: 0) {
            if boats.isEmpty {
                Text("No boats yet. Repositories you pin or own appear here.")
                    .font(.system(size: self.skin.row.detailSize + 1))
                    .foregroundStyle(self.skin.secondaryText)
                    .padding(self.skin.row.itemPadding)
            } else {
                LazyVGrid(columns: self.columns, alignment: .center, spacing: 8) {
                    ForEach(boats, id: \.boat.id) { entry in
                        Button { self.open(entry.repo) } label: {
                            BoatCell(boat: entry.boat)
                        }
                        .buttonStyle(.plain)
                        .help("\(entry.boat.name): \(entry.boat.condition.label)")
                        .accessibilityHint("Opens this repository")
                    }
                }
                .padding(.horizontal, self.skin.row.itemPadding)
                .padding(.vertical, 6)
                PanelSeparator()
                self.legend(boats.map(\.boat), total: self.repos.count)
            }
        }
    }

    private func legend(_ boats: [HarborBoat], total: Int) -> some View {
        let moored = boats.count(where: { $0.condition == .moored })
        let listing = boats.count(where: { $0.condition == .listing })
        let storm = boats.count(where: { $0.condition == .storm })
        return VStack(alignment: .leading, spacing: 3) {
            Text(Self.summary(moored: moored, listing: listing, storm: storm, shown: boats.count, total: total))
                .font(.system(size: self.skin.row.detailSize + 1, weight: .medium))
                .foregroundStyle(self.skin.text)
            Text("A listing boat has local drift; a storm is failing CI. Water height is how recent the latest activity is: full today, empty after 14 days.")
                .font(.system(size: self.skin.row.detailSize))
                .foregroundStyle(self.skin.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, self.skin.row.itemPadding)
        .padding(.bottom, 4)
    }

    /// "5 moored · 1 listing · 2 in a storm", with "showing 24 of 31" when capped.
    static func summary(moored: Int, listing: Int, storm: Int, shown: Int, total: Int) -> String {
        var parts = ["\(moored) moored"]
        if listing > 0 { parts.append("\(listing) listing") }
        if storm > 0 { parts.append("\(storm) in a storm") }
        var line = parts.joined(separator: " · ")
        if total > shown { line += " · showing \(shown) of \(total)" }
        return line
    }
}

private struct BoatCell: View {
    let boat: HarborBoat
    @Environment(\.harborPanelSkin) private var skin

    private var boatColor: Color {
        switch self.boat.condition {
        case .moored: self.skin.text
        case .listing: MenuInk.status(.pending)
        case .storm: MenuInk.status(.fail)
        }
    }

    var body: some View {
        VStack(spacing: 3) {
            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(self.skin.accent.opacity(0.28))
                    .frame(height: 6 + 14 * self.boat.tide)
                HarborBoatShape()
                    .fill(self.boatColor)
                    .frame(width: 22, height: 20)
                    .rotationEffect(.degrees(self.boat.condition == .listing ? 14 : 0), anchor: .bottom)
                    .padding(.bottom, 3 + 14 * self.boat.tide)
                if self.boat.condition == .storm {
                    Image(systemName: "cloud.bolt.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(self.boatColor)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(height: 46)
            .clipped()
            Text(self.boat.name)
                .font(.system(size: self.skin.row.detailSize))
                .foregroundStyle(self.skin.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(self.boat.name), \(self.boat.condition.label)")
    }
}
