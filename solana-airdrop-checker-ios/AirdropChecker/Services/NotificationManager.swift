import Foundation
import UserNotifications

final class NotificationManager: ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func requestPermissionIfNeeded() async -> Bool {
        await refreshAuthorizationStatus()

        if authorizationStatus == .authorized || authorizationStatus == .provisional {
            return true
        }

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            await refreshAuthorizationStatus()
            return granted
        } catch {
            return false
        }
    }

    func notifyNewAirdrops(_ events: [AirdropEvent]) async {
        guard !events.isEmpty else { return }
        guard await requestPermissionIfNeeded() else { return }

        let criticalCount = events.filter { $0.risk.level == .high }.count

        let content = UNMutableNotificationContent()
        if criticalCount > 0 {
            content.title = "Potential risky airdrop detected"
            content.body = "\(criticalCount) new token(s) flagged high risk. Review before interacting."
        } else {
            content.title = "New Solana airdrop activity"
            content.body = "\(events.count) token balance change(s) detected in your wallet."
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )

        do {
            try await center.add(request)
        } catch {
            // Ignore transient notification failures.
        }
    }
}
