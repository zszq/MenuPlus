import AppKit
import UserNotifications

enum FailurePresenter {
    static func present(action: String, reason: String) {
        NSLog("[MenuPlus/MainApp] 执行失败: %@ - %@", action, reason)

        Task { @MainActor in
            if await deliverNotificationIfAuthorized(action: action, reason: reason) {
                return
            }
            // 通知通道不可达（权限被拒/未授权/投递失败）时，前台场景用 NSAlert 兜底：
            // 设置页操作（如"打开方式"配置损坏的自救提示）若只剩 NSLog，用户完全看不到
            // 失败原因，自救流程会在无感知下推进。后台场景（Finder 右键经 IPC 触发、
            // App 未激活）不弹窗抢焦点，维持仅日志。
            guard NSApp.isActive else {
                return
            }
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "MenuPlus — \(action)失败"
            alert.informativeText = reason
            alert.runModal()
        }
    }

    /// 返回是否已成功投递通知；false 表示通知通道不可达，需要调用方另行兜底。
    private static func deliverNotificationIfAuthorized(action: String, reason: String) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return false
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
            return true
        } catch {
            NSLog("[MenuPlus/MainApp] 通知投递失败: %@", error.localizedDescription)
            return false
        }
    }
}
