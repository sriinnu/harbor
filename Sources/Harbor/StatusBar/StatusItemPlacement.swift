import AppKit
import Observation

/// Where macOS put Harbor's menu bar icon. A crowded menu bar on a notched Mac pushes
/// icons under the camera housing or off the bar, and macOS says nothing about it, so
/// Harbor checks and tells you in Settings.
enum StatusItemPlacement: Equatable {
    case visible
    case underNotch
    case offScreen
    /// Not enough information yet, for example before the item has a window.
    case unknown

    /// - Parameters:
    ///   - itemFrame: the status item button's window frame, in screen coordinates.
    ///   - screens: each screen's frame and, on notched displays, the gap between
    ///     `auxiliaryTopLeftArea` and `auxiliaryTopRightArea`.
    ///   - windowVisible: whether the window's occlusion state includes `.visible`.
    static func evaluate(itemFrame: CGRect?, screens: [ScreenInfo], windowVisible: Bool) -> Self {
        guard let itemFrame, itemFrame.width > 1, !screens.isEmpty else { return .unknown }
        guard let screen = screens.first(where: { $0.frame.intersects(itemFrame) }),
              screen.frame.intersection(itemFrame).width >= itemFrame.width / 2
        else { return .offScreen }
        if let notch = screen.notch {
            let covered = max(0, min(itemFrame.maxX, notch.maxX) - max(itemFrame.minX, notch.minX))
            // A sliver at the edge is the item's padding; a third of the item is the glyph.
            if covered >= itemFrame.width / 3 { return .underNotch }
        }
        return windowVisible ? .visible : .offScreen
    }

    var message: String? {
        switch self {
        case .visible, .unknown:
            nil
        case .underNotch:
            "Harbor's menu bar icon is under the camera notch. Hold ⌘ and drag it to the right, or remove a few menu bar icons."
        case .offScreen:
            "macOS hid Harbor's menu bar icon because the menu bar is full. Quit or remove a few menu bar icons, or hold ⌘ and drag Harbor further right."
        }
    }
}

struct ScreenInfo: Equatable {
    let frame: CGRect
    /// The camera housing's horizontal span, nil on displays without a notch.
    let notch: CGRect?

    @MainActor
    static func current() -> [Self] {
        NSScreen.screens.map { screen in
            var notch: CGRect?
            if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea, right.minX > left.maxX {
                notch = CGRect(x: left.maxX, y: left.minY, width: right.minX - left.maxX, height: left.height)
            }
            return Self(frame: screen.frame, notch: notch)
        }
    }
}

/// The latest placement, observed by Settings.
@MainActor
@Observable
final class StatusItemPresence {
    static let shared = StatusItemPresence()
    private(set) var placement: StatusItemPlacement = .unknown

    func update(_ placement: StatusItemPlacement) {
        if placement != self.placement { self.placement = placement }
    }
}
