import SwiftUI
import UserNotifications

@main
struct GlowUpApp: App {
    init() {
        // Show notifications while app is in foreground
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        _ = SubscriptionManager.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    await SubscriptionManager.shared.refreshEntitlements()
                }
        }
    }
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        if let destination = info["destination"] as? String {
            NotificationCenter.default.post(
                name: Notification.Name("GlowUpNotificationDestination"),
                object: nil,
                userInfo: ["destination": destination]
            )
        }
        completionHandler()
    }
}









