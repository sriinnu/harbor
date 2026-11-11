import AppKit
import SwiftUI

/// The fun way to read your repositories at a glance: one boat each, on a shared waterline.
struct HarborViewCard: View {
    let boats: [HarborBoat]

    private static let maxBoats = 8
    private static let sceneHeight: CGFloat = 46

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(self.boats.prefix(Self.maxBoats)) { boat in
                VStack(spacing: 3) {
                    HarborBoatScene(boat: boat).frame(height: Self.sceneHeight)
                    Text(boat.name)
                        .font(.system(size: 9))
                        .foregroundStyle(MenuHighlightStyle.secondary(false))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(boat.name), \(boat.condition.label)")
            }
        }
        .padding(.horizontal, MenuStyle.cardHorizontalPadding)
        .padding(.vertical, MenuStyle.cardVerticalPadding)
    }
}

private struct HarborBoatScene: View {
    let boat: HarborBoat

    private var water: Color {
        ActiveTheme.palette?.accent.color ?? Color(nsColor: .systemBlue)
    }

    private var boatColor: Color {
        switch self.boat.condition {
        case .moored: MenuHighlightStyle.primary(false)
        case .listing: MenuHighlightStyle.warning(false)
        case .storm: MenuHighlightStyle.error(false)
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(self.water.opacity(0.28))
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
        .clipped()
    }
}

private struct HarborBoatShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        var path = Path()
        // Hull.
        path.move(to: CGPoint(x: 0, y: height * 0.68))
        path.addLine(to: CGPoint(x: width, y: height * 0.68))
        path.addLine(to: CGPoint(x: width * 0.82, y: height))
        path.addLine(to: CGPoint(x: width * 0.18, y: height))
        path.closeSubpath()
        // Sail.
        path.move(to: CGPoint(x: width * 0.5, y: 0))
        path.addLine(to: CGPoint(x: width * 0.88, y: height * 0.58))
        path.addLine(to: CGPoint(x: width * 0.5, y: height * 0.58))
        path.closeSubpath()
        // Jib.
        path.move(to: CGPoint(x: width * 0.42, y: height * 0.14))
        path.addLine(to: CGPoint(x: width * 0.42, y: height * 0.58))
        path.addLine(to: CGPoint(x: width * 0.14, y: height * 0.58))
        path.closeSubpath()
        return path
    }
}
