import AppKit
import Combine
import FinderSync
import UserNotifications

enum BundleInstallState {
    case applications
    case derivedData
    case other
}

@MainActor
final class AppRuntime: ObservableObject {
    static let shared = AppRuntime()

    @Published private(set) var showsMenuBarIcon: Bool
    @Published private(set) var isFinderExtensionEnabled = FIFinderSyncController.isExtensionEnabled
    @Published private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var bundleInstallState: BundleInstallState = .other
    @Published private(set) var authorizedDirectoryPaths: [String] = []

    private var hasPresentedDisabledExtensionAlertThisLaunch = false
    private var hasPresentedBundleLocationAlertThisLaunch = false

    private enum DefaultsKey {
        static let showsMenuBarIcon = "showsMenuBarIcon"
    }

    private init() {
        if UserDefaults.standard.object(forKey: DefaultsKey.showsMenuBarIcon) == nil {
            showsMenuBarIcon = true
        } else {
            showsMenuBarIcon = UserDefaults.standard.bool(forKey: DefaultsKey.showsMenuBarIcon)
        }
    }

    func refreshStatus() {
        isFinderExtensionEnabled = FIFinderSyncController.isExtensionEnabled
        bundleInstallState = detectBundleInstallState()
        refreshAuthorizedDirectories()

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
                if error != nil {
                    SystemSettingsNavigator.openNotificationsPrivacy()
                }
            }
        }
    }

    func setShowsMenuBarIcon(_ isShown: Bool) {
        guard showsMenuBarIcon != isShown else { return }

        showsMenuBarIcon = isShown
        UserDefaults.standard.set(isShown, forKey: DefaultsKey.showsMenuBarIcon)
    }

    func presentStartupGuidanceIfNeeded() {
        refreshStatus()

        if shouldPresentBundleLocationGuidance, !hasPresentedBundleLocationAlertThisLaunch {
            hasPresentedBundleLocationAlertThisLaunch = true
            presentBundleLocationGuidance()
            return
        }

        guard !isFinderExtensionEnabled, !hasPresentedDisabledExtensionAlertThisLaunch else {
            return
        }

        hasPresentedDisabledExtensionAlertThisLaunch = true
        presentFinderExtensionGuidance()
    }

    var bundleLocationPath: String {
        Bundle.main.bundleURL.path
    }

    var bundleLocationSummary: String {
        switch bundleInstallState {
        case .applications:
            return "应用程序"
        case .derivedData:
            return "Xcode DerivedData"
        case .other:
            return "自定义位置"
        }
    }

    var bundleLocationGuidanceText: String {
        switch bundleInstallState {
        case .applications:
            return "当前已从 /Applications 运行，适合验证 Finder 扩展启用链路。"
        case .derivedData:
            return "当前正在从 Xcode DerivedData 运行。Finder 扩展在这种路径下经常会出现“系统已注册但设置页不稳定”的情况，建议复制到 /Applications 后再启用。"
        case .other:
            return "当前不是从 /Applications 运行。若 Finder 扩展状态反复异常，建议复制到 /Applications 后再重新启用。"
        }
    }

    private var shouldPresentBundleLocationGuidance: Bool {
        bundleInstallState != .applications
    }

    private func detectBundleInstallState() -> BundleInstallState {
        let path = bundleLocationPath
        if path.hasPrefix("/Applications/") {
            return .applications
        }
        if path.contains("/DerivedData/") {
            return .derivedData
        }
        return .other
    }

    private func presentBundleLocationGuidance() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "建议从 /Applications 启用 MenuPlus"
        alert.informativeText = """
        MenuPlus 是 Finder 扩展，不会出现在“文件提供程序”里；请去“系统设置 → 隐私与安全性 → 扩展 → Finder 扩展”启用。

        \(bundleLocationGuidanceText)

        当前运行位置：
        \(bundleLocationPath)
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "显示当前 App")
        alert.addButton(withTitle: "打开扩展管理")
        alert.addButton(withTitle: "稍后")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            revealCurrentAppInFinder()
        case .alertSecondButtonReturn:
            openFinderExtensionManagement()
        default:
            break
        }
    }

    func presentFinderExtensionGuidance() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "启用 Finder 扩展"
        alert.informativeText = """
        MenuPlus 的右键菜单依赖 Finder 扩展。

        请前往“系统设置 → 隐私与安全性 → 扩展 → Finder 扩展”启用 MenuPlus。
        注意：它不会出现在“文件提供程序”里。

        启用后回到这里点一次“刷新状态”即可。
        """
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

    func revealCurrentAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    func refreshAuthorizedDirectories() {
        do {
            authorizedDirectoryPaths = try SecurityScopedDirectoryStore.authorizedDirectoryPaths()
        } catch {
            NSLog("[MenuPlus/MainApp] 加载已授权目录失败: %@", error.localizedDescription)
            authorizedDirectoryPaths = []
        }
    }

    func authorizeDirectoriesFromSettings() {
        do {
            let changed = try SecurityScopedDirectoryStore.authorizeDirectoriesFromSettings()
            if changed {
                refreshAuthorizedDirectories()
            }
        } catch {
            FailurePresenter.present(action: "添加授权目录", reason: error.localizedDescription)
        }
    }

    func removeAuthorizedDirectories(_ directoryPaths: [String]) {
        do {
            try SecurityScopedDirectoryStore.removeAuthorizedDirectories(directoryPaths)
            refreshAuthorizedDirectories()
        } catch {
            FailurePresenter.present(action: "移除授权目录", reason: error.localizedDescription)
        }
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
