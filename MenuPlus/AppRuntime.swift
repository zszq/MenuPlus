import AppKit
import Combine
import FinderSync
import UserNotifications

@MainActor
final class AppRuntime: ObservableObject {
    static let shared = AppRuntime()

    @Published private(set) var isFinderExtensionEnabled = FIFinderSyncController.isExtensionEnabled
    @Published private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined

    private var hasPresentedDisabledExtensionAlertThisLaunch = false

    private init() {}

    func refreshStatus() {
        isFinderExtensionEnabled = FIFinderSyncController.isExtensionEnabled

        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            await MainActor.run {
                self.notificationStatus = settings.authorizationStatus
            }
        }
    }

    func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error {
                NSLog("[MenuPlus/MainApp] 通知权限申请失败: %@", error.localizedDescription)
            }
            Task { @MainActor in
                self.refreshStatus()
            }
        }
    }

    func presentStartupGuidanceIfNeeded() {
        refreshStatus()

        guard !isFinderExtensionEnabled, !hasPresentedDisabledExtensionAlertThisLaunch else {
            return
        }

        hasPresentedDisabledExtensionAlertThisLaunch = true
        presentFinderExtensionGuidance()
    }

    func presentFinderExtensionGuidance() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "启用 Finder 扩展"
        alert.informativeText = "MenuPlus 的右键菜单依赖 Finder 扩展。请在系统弹出的扩展管理界面中启用 MenuPlus；启用后回到这里点一次“刷新状态”即可。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "打开扩展管理")
        alert.addButton(withTitle: "稍后")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openFinderExtensionManagement()
        }
    }

    func openFinderExtensionManagement() {
        if #available(macOS 10.14, *) {
            FIFinderSyncController.showExtensionManagementInterface()
            return
        }

        SystemSettingsNavigator.openExtensionsFallback()
    }
}

extension UNUserNotificationCenter {
    func notificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }
}

enum SystemSettingsNavigator {
    static func openExtensionsFallback() {
        if let finderExtURL = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences?Finder"),
           NSWorkspace.shared.open(finderExtURL) {
            return
        }

        if let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.extensions") {
            NSWorkspace.shared.open(fallback)
        }
    }

    static func openAutomationPrivacy() {
        if let automationURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"),
           NSWorkspace.shared.open(automationURL) {
            return
        }

        if let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(fallback)
        }
    }

    static func openNotificationsPrivacy() {
        if let notificationsURL = URL(string: "x-apple.systempreferences:com.apple.preference.notifications"),
           NSWorkspace.shared.open(notificationsURL) {
            return
        }

        if let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(fallback)
        }
    }
}
