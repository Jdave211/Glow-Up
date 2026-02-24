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
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
        }
    }

    private func handleIncomingURL(_ url: URL) {
        guard let token = extractSharedRoutineToken(from: url) else { return }
        SessionManager.shared.queueSharedRoutineToken(token)
        NotificationCenter.default.post(
            name: .glowUpOpenRoutineImport,
            object: nil,
            userInfo: ["token": token]
        )
        NotificationCenter.default.post(
            name: .glowUpNotificationDestination,
            object: nil,
            userInfo: ["destination": "routine"]
        )
    }

    private func extractSharedRoutineToken(from url: URL) -> String? {
        if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let token = comps.queryItems?.first(where: { $0.name == "token" })?.value,
           !token.isEmpty {
            return token
        }

        // Support web-form links like /share/routine/:token when opened directly by the app.
        let pathParts = url.pathComponents.filter { $0 != "/" }
        if pathParts.count >= 3,
           pathParts[pathParts.count - 3] == "share",
           pathParts[pathParts.count - 2] == "routine" {
            let token = pathParts[pathParts.count - 1]
            return token.isEmpty ? nil : token
        }
        return nil
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
                name: .glowUpNotificationDestination,
                object: nil,
                userInfo: ["destination": destination]
            )
        }
        completionHandler()
    }
}







