import SwiftUI
import AppKit

struct StatusItemLabelView: View {
    @Bindable var session: Session
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let status = self.aggregateStatus()
        let badgeSymbol = self.badgeSymbol(for: status)

        ZStack(alignment: .bottomTrailing) {
            // Use custom Harbor anchor icon
            if let anchorImage = self.loadMenuBarIcon() {
                Image(nsImage: anchorImage)
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
            } else {
                // Fallback to SF Symbol if custom icon fails to load
                Image(systemName: status == .loggedOut ? "tray" : "tray.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 14, weight: .regular))
            }

            if let badgeSymbol {
                Image(systemName: badgeSymbol)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 7, weight: .semibold))
                    .offset(x: 4, y: 2)
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityLabel("Harbor")
        .onAppear {
            SettingsOpener.shared.configure {
                self.openSettings()
            }
            self.presentLoginSettingsIfNeeded()
        }
    }

    private func aggregateStatus() -> AggregateStatus {
        if self.session.account == .loggedOut { return .loggedOut }
        if self.session.repositories.contains(where: { $0.ciStatus == .failing }) { return .red }
        if self.session.repositories.contains(where: { $0.ciStatus == .pending }) { return .yellow }
        return .green
    }

    private func badgeSymbol(for status: AggregateStatus) -> String? {
        switch status {
        case .green: "smallcircle.filled.circle"
        case .yellow: "exclamationmark.circle.fill"
        case .red: "xmark.circle.fill"
        case .loggedOut: "slash.circle"
        }
    }

    private func presentLoginSettingsIfNeeded() {
        guard case .loggedOut = self.session.account else { return }
        self.session.settingsSelectedTab = .accounts
        SettingsOpener.shared.open()
    }

    private func loadMenuBarIcon() -> NSImage? {
        // Try to load from bundle resources
        guard let resourcePath = Bundle.main.resourcePath else { return nil }
        let iconPath = resourcePath + "/MenuBarIcons/anchor-mono.svg"

        // Try loading SVG as NSImage
        if let svgData = try? Data(contentsOf: URL(fileURLWithPath: iconPath)),
           let image = NSImage(data: svgData) {
            image.isTemplate = true // Makes it adapt to light/dark mode
            return image
        }

        // Alternative: try loading from app bundle
        if let bundleURL = Bundle.main.url(forResource: "anchor-mono", withExtension: "svg", subdirectory: "MenuBarIcons"),
           let svgData = try? Data(contentsOf: bundleURL),
           let image = NSImage(data: svgData) {
            image.isTemplate = true
            return image
        }

        return nil
    }
}

private enum AggregateStatus {
    case loggedOut
    case green
    case yellow
    case red
}
