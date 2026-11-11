import AppKit
import HarborCore
import QuartzCore
import SwiftUI

/// Dresses a built menu in the active theme. The native theme leaves it untouched.
/// AppKit can't recolor plain menu items, so each one gets a drawn row that keeps the
/// item's own target, action and submenu.
@MainActor
struct ThemedMenuSkin {
    let menuBuilder: StatusBarMenuBuilder

    func restyleItems(in menu: NSMenu) {
        guard ActiveTheme.palette != nil else { return }
        for (index, item) in menu.items.enumerated().reversed() where item.view == nil && !item.isAlternate {
            if item.isSeparatorItem {
                menu.removeItem(at: index)
                menu.insertItem(self.menuBuilder.viewItem(for: ThemedMenuRule(), enabled: false), at: index)
            } else {
                self.drawRow(for: item)
            }
        }
    }

    private func drawRow(for item: NSMenuItem) {
        let hasSubmenu = item.submenu != nil
        let row = ThemedMenuRow(
            title: item.title,
            image: item.image,
            isChecked: item.state == .on,
            isEnabled: item.isEnabled,
            onOpen: hasSubmenu || !item.isEnabled ? nil : { [weak item] in
                guard let item else { return }
                Self.perform(item)
            }
        )
        item.view = MenuItemViewFactory().makeItem(
            for: row,
            enabled: item.isEnabled,
            highlightable: item.isEnabled,
            showsSubmenuIndicator: hasSubmenu
        ).view
        if hasSubmenu, item.action == nil {
            item.target = self.menuBuilder.target
            item.action = #selector(StatusBarMenuManager.menuItemNoOp(_:))
        }
    }

    /// A custom view swallows the click AppKit would have turned into the item's action.
    private static func perform(_ item: NSMenuItem) {
        var root = item.menu
        while let parent = root?.supermenu { root = parent }
        root?.cancelTracking()
        guard let action = item.action else { return }
        NSApp.sendAction(action, to: item.target, from: item)
    }
}

/// An opaque fill and ruled border behind the menu's rows.
final class ThemedMenuBackdrop: NSView {
    private let palette: HarborThemePalette

    /// Makes `window` show the active theme's backdrop, or none for the native theme.
    static func sync(in window: NSWindow) {
        window.appearance = ActiveTheme.menuAppearance
        guard let content = window.contentView else { return }
        let existing = content.subviews.compactMap { $0 as? ThemedMenuBackdrop }
        guard existing.first?.palette != ActiveTheme.palette else { return }
        existing.forEach { $0.removeFromSuperview() }
        guard let palette = ActiveTheme.palette else { return }
        let backdrop = ThemedMenuBackdrop(frame: content.bounds, palette: palette, theme: ActiveTheme.theme)
        backdrop.autoresizingMask = [.width, .height]
        content.addSubview(backdrop, positioned: .below, relativeTo: content.subviews.first)
    }

    init(frame: NSRect, palette: HarborThemePalette, theme: HarborTheme) {
        self.palette = palette
        super.init(frame: frame)
        self.wantsLayer = true
        self.layer?.backgroundColor = palette.background.nsColor.cgColor
        self.layer?.borderColor = palette.border.nsColor.cgColor
        self.layer?.borderWidth = theme.menuBorderWidth
        if theme.hasInsetRule {
            let rule = CALayer()
            rule.frame = self.bounds.insetBy(dx: 4, dy: 4)
            rule.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            rule.borderColor = palette.border.nsColor.cgColor
            rule.borderWidth = 1
            self.layer?.addSublayer(rule)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_: NSPoint) -> NSView? { nil }
}

struct ThemedMenuRule: View {
    var body: some View {
        Rectangle()
            .fill(ActiveTheme.palette?.separator.color ?? .secondary)
            .frame(height: ActiveTheme.theme.menuBorderWidth >= 2 ? 2 : 1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
    }
}

struct ThemedMenuRow: View {
    let title: String
    let image: NSImage?
    let isChecked: Bool
    let isEnabled: Bool
    let onOpen: (() -> Void)?
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        if let onOpen {
            self.row.contentShape(Rectangle()).onTapGesture(perform: onOpen)
        } else {
            self.row
        }
    }

    private var foreground: Color {
        guard self.isEnabled else { return ActiveTheme.palette?.tertiaryText.color ?? .secondary }
        return MenuHighlightStyle.primary(self.isHighlighted)
    }

    private var row: some View {
        HStack(spacing: MenuStyle.submenuIconSpacing) {
            SubmenuIconColumnView {
                if self.isChecked {
                    Image(systemName: "checkmark").font(.caption.weight(.semibold))
                } else if let image = self.image {
                    Image(nsImage: image).renderingMode(.template)
                }
            }
            Text(self.title).font(.system(size: 14)).lineLimit(1)
            Spacer(minLength: 8)
        }
        .foregroundStyle(self.foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }
}

/// The repository status mark: the theme's signal flag, or the standard dot.
struct CIStatusMark<Dot: View>: View {
    let status: CIStatus
    @ViewBuilder let dot: Dot

    var body: some View {
        if ActiveTheme.theme.usesSignalFlags {
            SignalFlagView(status: self.status).frame(width: 14, height: 10)
        } else {
            self.dot
        }
    }
}

private struct SignalFlagView: View {
    let status: CIStatus

    @MainActor private static let blue = HarborThemeColor(hex: 0x00247D).color
    @MainActor private static let red = HarborThemeColor(hex: 0xC8102E).color
    @MainActor private static let yellow = HarborThemeColor(hex: 0xFFC400).color

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let ink = ActiveTheme.palette?.text.color ?? .primary
            switch self.status {
            case .passing:
                context.fill(Path(rect), with: .color(.white))
                for (band, color) in [(0, Self.blue), (2, Self.red), (4, Self.blue)] {
                    let bandRect = CGRect(x: 0, y: size.height * CGFloat(band) / 5, width: size.width, height: size.height / 5)
                    context.fill(Path(bandRect), with: .color(color))
                }
            case .failing:
                context.fill(Path(rect), with: .color(.white))
                var saltire = Path()
                saltire.move(to: .zero)
                saltire.addLine(to: CGPoint(x: size.width, y: size.height))
                saltire.move(to: CGPoint(x: size.width, y: 0))
                saltire.addLine(to: CGPoint(x: 0, y: size.height))
                context.stroke(saltire, with: .color(Self.red), lineWidth: 2)
            case .pending:
                context.fill(Path(rect), with: .color(Self.yellow))
            case .unknown:
                var pennant = Path()
                pennant.move(to: .zero)
                pennant.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                pennant.addLine(to: CGPoint(x: 0, y: size.height))
                pennant.closeSubpath()
                context.fill(pennant, with: .color(ink))
                return
            }
            context.stroke(Path(rect), with: .color(ink), lineWidth: 1)
        }
    }
}
