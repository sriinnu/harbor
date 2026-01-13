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
            HarborIconView(size: 18)

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
}

private enum AggregateStatus {
    case loggedOut
    case green
    case yellow
    case red
}

#if DEBUG
struct StatusItemLabelView_Previews: PreviewProvider {
    static var previews: some View {
        StatusItemLabelView(session: Session())
            .frame(width: 22, height: 22)
            .padding()
    }
}
#endif
