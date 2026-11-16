import Foundation
import HarborCore
import UserNotifications

actor LocalSyncNotifier {
    static let shared = LocalSyncNotifier()
    private let center: UNUserNotificationCenter?

    init() {
        if Bundle.main.bundleURL.pathExtension == "app" {
            self.center = UNUserNotificationCenter.current()
        } else {
            self.center = nil
        }
    }

    func notifySync(for status: LocalRepoStatus) async {
        await self.notify(body: "Synced \(status.displayName) (\(status.branch))")
    }

    /// Posts one notification titled "Harbor", asking for permission the first time.
    func notify(body: String) async {
        guard let center = self.center else { return }

        let authorizationStatus = await self.authorizationStatus(using: center)
        let authorized: Bool = switch authorizationStatus {
        case .authorized, .provisional:
            true
        case .notDetermined:
            await self.requestAuthorization(using: center)
        default:
            false
        }

        guard authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Harbor"
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        _ = try? await center.add(request)
    }

    private func authorizationStatus(using center: UNUserNotificationCenter) async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    private func requestAuthorization(using center: UNUserNotificationCenter) async -> Bool {
        await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }
}
