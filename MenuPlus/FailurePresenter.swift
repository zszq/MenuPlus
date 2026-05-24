import AppKit
import UserNotifications

enum FailureGuidance {
    case automation(targetApp: String)
}

enum FailurePresenter {
    static func present(action: String, reason: String, guidance: FailureGuidance? = nil) {
        NSLog("[MenuPlus/MainApp] 执行失败: %@ - %@", action, reason)

        Task { @MainActor in
            if let guidance {
                presentGuidanceAlert(for: guidance, action: action, reason: reason)
            }

            await deliverNotificationIfAuthorized(action: action, reason: reason)
        }
    }

    @MainActor
    private static func presentGuidanceAlert(for guidance: FailureGuidance, action: String, reason: String) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(action)需要额外授权"

        switch guidance {
        case .automation(let targetApp):
            alert.informativeText = "\(reason)\n\n请前往“系统设置 → 隐私与安全性 → 自动化”，允许 MenuPlus 控制\(targetApp)，然后回到 Finder 重试。"
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "知道了")
            if alert.runModal() == .alertFirstButtonReturn {
                SystemSettingsNavigator.openAutomationPrivacy()
            }
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
