import HarborCore
import SwiftUI

/// One row the keyboard can land on. Equality is by id so a changed closure doesn't churn
/// the preference.
struct PanelNavItem: Equatable, @unchecked Sendable {
    let id: String
    /// Rows with a chevron also open on the Right arrow.
    let drillsIn: Bool
    let perform: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id && lhs.drillsIn == rhs.drillsIn }
}

struct PanelNavKey: PreferenceKey {
    static let defaultValue: [PanelNavItem] = []

    static func reduce(value: inout [PanelNavItem], nextValue: () -> [PanelNavItem]) {
        value += nextValue()
    }
}

/// Keyboard state of the panel: which row is selected, and what the arrows, Return and
/// Escape do. The mouse writes `selected` too, so hover and the keyboard share one highlight.
@MainActor
@Observable
final class PanelNavigator {
    var selected: String?
    /// Set only by the keyboard; the scroll view follows it.
    var scrollRequest: String?
    private(set) var items: [PanelNavItem] = []
    /// Leaves the repo detail if it is open; returns whether it did.
    var goBack: () -> Bool = { false }
    /// Command-key shortcuts by typed character (",", "q"); set by the panel view, so they
    /// work from the repo detail too, where the footer is not on screen.
    /// Opens a repo's detail by full name (the first repo for nil). Set by the panel view; the
    /// snapshot tool uses it to render the detail pane.
    var showRepo: (String?) -> Void = { _ in }
    /// Opens a pull request's pane (repo full name, number); the snapshot tool uses it.
    var showPull: (String, Int) -> Void = { _, _ in }
    var commands: [String: () -> Void] = [:]
    /// Opens the Tower tab, and its first worktree's detail when asked; the snapshot tool uses it.
    var showTower: (_ openFirst: Bool) -> Void = { _ in }
    /// Opens a list pane over the open repo detail, and the Harbor tab; the snapshot tool uses them.
    var showList: (RepoListKind) -> Void = { _ in }
    var showHarbor: (Bool) -> Void = { _ in }

    /// Type-to-filter: what was typed, and where it applies. `filterRowPrefix` is the id prefix
    /// of the rows it narrows (nil where typing does nothing: details, Tower, a pull request).
    private(set) var filter = ""
    private(set) var filterRowPrefix: String?

    /// Called by the panel view as the screen changes; a different list starts with no filter.
    func setFilterScope(_ prefix: String?) {
        guard prefix != self.filterRowPrefix else { return }
        self.filterRowPrefix = prefix
        self.filter = ""
    }

    /// Takes typed characters into the filter. Returns whether it did: not while a confirm or
    /// a running action pins the panel, not where nothing is filterable, and a leading space
    /// is not a search.
    func type(_ characters: String) -> Bool {
        guard self.filterRowPrefix != nil, !self.isPinnedOpen, NameFilter.isSearchText(characters) else { return false }
        if self.filter.isEmpty, characters.allSatisfy(\.isWhitespace) { return false }
        self.filter += characters
        self.selected = nil
        return true
    }

    /// Delete removes the last typed character; false when there is no filter to edit.
    func deleteBackward() -> Bool {
        guard self.filterRowPrefix != nil, !self.filter.isEmpty, !self.isPinnedOpen else { return false }
        self.filter.removeLast()
        self.selected = nil
        return true
    }

    /// Escape's first job: clears the filter. False when there was none, so Escape goes on.
    func clearFilter() -> Bool {
        guard !self.filter.isEmpty else { return false }
        self.filter = ""
        self.selected = nil
        return true
    }

    /// Reasons the panel must stay open (a confirm or a running action). See `pinsPanelOpen`.
    private(set) var pinReasons: Set<String> = []
    var isPinnedOpen: Bool { !self.pinReasons.isEmpty }

    func pin(_ reason: String, _ on: Bool) {
        if on { self.pinReasons.insert(reason) } else { self.pinReasons.remove(reason) }
    }

    func handle(command key: String) -> Bool {
        guard let run = self.commands[key.lowercased()] else { return false }
        run()
        return true
    }

    func update(_ items: [PanelNavItem]) {
        self.items = items
        if let selected, !items.contains(where: { $0.id == selected }) { self.selected = nil }
    }

    func reset() {
        self.selected = nil
    }

    func move(_ delta: Int) {
        guard !self.items.isEmpty else { return }
        let current = self.items.firstIndex { $0.id == self.selected }
        let next: Int = if let current {
            min(max(current + delta, 0), self.items.count - 1)
        } else {
            delta > 0 ? 0 : self.items.count - 1
        }
        self.selected = self.items[next].id
        self.scrollRequest = self.selected
    }

    /// The footer is one row of icon buttons, so Left and Right walk it.
    private var inFooter: Bool { self.selected?.hasPrefix(PanelFooterBar.idPrefix) == true }

    private func moveInFooter(_ delta: Int) {
        let footer = self.items.filter { $0.id.hasPrefix(PanelFooterBar.idPrefix) }
        guard let current = footer.firstIndex(where: { $0.id == self.selected }) else { return }
        self.selected = footer[min(max(current + delta, 0), footer.count - 1)].id
    }

    func activate(requiringDrillIn: Bool = false) {
        // With a filter and nothing highlighted, Return opens the first match.
        if self.selected == nil, !self.isPinnedOpen, !self.filter.isEmpty, let prefix = self.filterRowPrefix,
           let first = self.items.first(where: { $0.id.hasPrefix(prefix) }) {
            if !requiringDrillIn { first.perform() }
            return
        }
        guard let item = self.items.first(where: { $0.id == self.selected }) else { return }
        if requiringDrillIn, !item.drillsIn { return }
        item.perform()
    }

    /// Handles a key press. Returns whether the panel consumed it.
    func handle(keyCode: UInt16) -> Bool {
        switch keyCode {
        case 125: self.move(1)
        case 126: self.move(-1)
        case 36, 76: self.activate()
        case 51: return self.deleteBackward()
        case 124:
            if self.inFooter { self.moveInFooter(1) } else { self.activate(requiringDrillIn: true) }
        case 123:
            if self.inFooter { self.moveInFooter(-1) } else { return self.goBack() }
        default: return false
        }
        return true
    }
}

private struct PanelNavigatorKey: EnvironmentKey {
    static let defaultValue: PanelNavigator? = nil
}

extension EnvironmentValues {
    var panelNavigator: PanelNavigator? {
        get { self[PanelNavigatorKey.self] }
        set { self[PanelNavigatorKey.self] = newValue }
    }

    /// The tallest the panel may be; its list scrolls past that.
    var panelMaxHeight: CGFloat {
        get { self[PanelMaxHeightKey.self] }
        set { self[PanelMaxHeightKey.self] = newValue }
    }
}

private struct PanelMaxHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 800
}
