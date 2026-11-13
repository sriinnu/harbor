import AppKit
import SwiftUI

/// The theme's separator: a thin rule inset from both edges (brass in Navy, heavy ink in
/// the comic and high-contrast designs).
struct PanelSeparator: View {
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        Rectangle()
            .fill(self.skin.separator)
            .frame(height: self.skin.separatorWidth)
            .padding(.horizontal, self.skin.separatorInset)
            .padding(.vertical, 5)
            .accessibilityHidden(true)
    }
}

/// A clickable row with one highlight shared by the mouse and the keyboard: the theme's
/// selection fill (and ring), with `menuItemHighlighted` set so the row's own colors flip
/// to selection text.
struct PanelRow<Content: View>: View {
    let id: String
    var showsChevron = false
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    @Environment(\.harborPanelSkin) private var skin
    @Environment(\.panelNavigator) private var navigator

    var body: some View {
        let selected = self.navigator?.selected == self.id
        Button(action: self.action) {
            HStack(spacing: 0) {
                self.content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                if self.showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(selected ? self.skin.selectionText : self.skin.tertiaryText)
                        .padding(.trailing, 8)
                        .accessibilityHidden(true)
                }
            }
            .background { if selected { PanelSelectionShape() } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .environment(\.menuItemHighlighted, selected)
        .onHover { inside in
            if inside {
                self.navigator?.selected = self.id
            } else if self.navigator?.selected == self.id {
                self.navigator?.selected = nil
            }
        }
        .id(self.id)
        .preference(key: PanelNavKey.self, value: [PanelNavItem(id: self.id, drillsIn: self.showsChevron, perform: self.action)])
    }
}

/// The selected row's fill and ring.
struct PanelSelectionShape: View {
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        let radius = self.skin.itemRadius
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(self.skin.selection)
            if let ring = self.skin.selectionRing {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(ring.outer.color, lineWidth: ring.outer.width)
                if let inner = ring.inner {
                    RoundedRectangle(cornerRadius: max(radius - ring.outer.width, 0), style: .continuous)
                        .inset(by: ring.outer.width)
                        .strokeBorder(inner.color, lineWidth: inner.width)
                }
            }
        }
    }
}

/// What the panel is painted on: gradient, paper or a system material.
struct PanelSurface: View {
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        switch self.skin.surface {
        case let .gradient(stops):
            // The design's stops sit at 0%, 42% and 100%.
            LinearGradient(
                stops: [
                    .init(color: stops[0], location: 0),
                    .init(color: stops[1], location: 0.42),
                    .init(color: stops[2], location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case let .solid(color):
            color
        case let .material(material):
            VisualEffectBackground(material: material, cornerRadius: self.skin.cornerRadius)
        }
    }
}

/// A behind-window blur, so Liquid Glass follows light and dark and shows what is under it.
struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let cornerRadius: CGFloat

    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        self.configure(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context _: Context) {
        self.configure(view)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.material = self.material
        // The blur ignores SwiftUI clipping; the mask is what rounds its corners.
        let radius = self.cornerRadius
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        view.maskImage = image
    }
}

/// A banner: all clear, rate limited, or an error.
struct PanelNotice: View {
    let kind: StatusGlyph.Kind
    let text: String
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        let notice = self.notice
        HStack(alignment: .top, spacing: 8) {
            StatusGlyph(kind: self.kind, size: self.skin.row.glyphSize)
            Text(self.text)
                .font(.system(size: self.skin.row.detailSize + 1, weight: .medium))
                .foregroundStyle(notice.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: self.skin.noticeRadius, style: .continuous).fill(notice.fill))
        .overlay {
            if let edge = notice.edge {
                RoundedRectangle(cornerRadius: self.skin.noticeRadius, style: .continuous)
                    .strokeBorder(edge.color, lineWidth: edge.width)
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Self.spokenKind(self.kind)): \(self.text)")
    }

    /// The lamp is hidden from VoiceOver, so the banner says how serious it is.
    static func spokenKind(_ kind: StatusGlyph.Kind) -> String {
        switch kind {
        case .fail: "Error"
        case .pass: "OK"
        default: "Warning"
        }
    }

    private var notice: HarborPanelSkin.Notice {
        switch self.kind {
        case .pass: self.skin.ok
        case .fail:
            HarborPanelSkin.Notice(
                fill: MenuInk.status(.fail).opacity(0.14), text: self.skin.warn.text,
                edge: HarborPanelSkin.Edge(color: MenuInk.status(.fail), width: self.skin.warn.edge?.width ?? 1)
            )
        default: self.skin.warn
        }
    }
}

/// The design's segmented control: a track with the chosen segment filled.
struct PanelSegmented<Option: Hashable>: View {
    let options: [Option]
    let label: KeyPath<Option, String>
    @Binding var selection: Option
    var segmentPadding: CGFloat = 10
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        let outer = self.shape(self.skin.segmentRadius)
        let inner = self.shape(self.skin.segmentRadius - 2)
        HStack(spacing: 2) {
            ForEach(self.options, id: \.self) { option in
                let isOn = option == self.selection
                Button { self.selection = option } label: {
                    Text(option[keyPath: self.label])
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isOn ? self.skin.segmentOnText : self.skin.text)
                        .padding(.horizontal, self.segmentPadding)
                        .frame(height: 20)
                        .background { if isOn { inner.fill(self.skin.segmentOnFill) } }
                        .overlay {
                            if isOn, let ring = self.skin.segmentOnRing {
                                inner.inset(by: 0.75).strokeBorder(ring, lineWidth: 1.5)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(2)
        .accessibilityElement(children: .contain)
        .background(outer.fill(self.skin.segmentFill))
        .overlay {
            if let edge = self.skin.segmentEdge { outer.strokeBorder(edge.color, lineWidth: edge.width) }
        }
    }

    private func shape(_ radius: CGFloat) -> some InsettableShape {
        RoundedRectangle(cornerRadius: max(min(radius, 10), 0), style: .continuous)
    }
}

/// "Settings…  ⌘," and friends.
struct PanelCommandLabel: View {
    let title: String
    let shortcut: String?
    @Environment(\.menuItemHighlighted) private var isHighlighted
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        HStack {
            Text(self.title)
                .foregroundStyle(self.isHighlighted ? self.skin.selectionText : self.skin.text)
            Spacer()
            if let shortcut {
                Text(shortcut)
                    .font(.system(size: self.skin.row.detailSize + 1))
                    .foregroundStyle(self.isHighlighted ? self.skin.selectionText : self.skin.tertiaryText)
            }
        }
        .font(.system(size: self.skin.row.nameSize))
        .padding(.horizontal, self.skin.row.itemPadding)
        .frame(height: self.skin.itemHeight)
    }
}

struct PanelPrimaryButtonStyle: ButtonStyle {
    @Environment(\.harborPanelSkin) private var skin
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: min(self.skin.segmentRadius, 14), style: .continuous)
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(self.skin.primaryText)
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(shape.fill(self.skin.primaryFill))
            .overlay {
                if let edge = self.skin.segmentEdge { shape.strokeBorder(edge.color, lineWidth: edge.width) }
            }
            .opacity(self.isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}
