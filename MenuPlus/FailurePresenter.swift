import AppKit
import UserNotifications

enum FailurePresenter {
    static func present(action: String, reason: String) {
        NSLog("[MenuPlus/MainApp] 执行失败: %@ - %@", action, reason)

        Task {
            await deliverNotificationIfAuthorized(action: action, reason: reason)
        }
    }

    private static func deliverNotificationIfAuthorized(action: String, reason: String) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "MenuPlus — \(action)失败"
        content.body = reason

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
        } catch {
            NSLog("[MenuPlus/MainApp] 通知投递失败: %@", error.localizedDescription)
        }
    }
}
