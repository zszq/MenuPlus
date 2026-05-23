//
//  rightMenuApp.swift
//  rightMenu
//
//  Created by l z on 2026/5/12.
//

import SwiftUI
import AppKit
import UserNotifications

@main
struct rightMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 使用 MenuBarExtra 提供菜单栏图标
        // LSUIElement=YES 已在 Info.plist 中设置，确保无 Dock 图标
        MenuBarExtra("rightMenu", systemImage: "filemenu.and.cursorarrow") {
            MenuBarView()
        }
        // 注：MenuBarExtra Scene 不支持 .onOpenURL，
        // URL 处理放在 AppDelegate 的 application(_:open:) 中。
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 申请通知权限：扩展端动作失败时由主 App 投递通知
        // 被拒也无所谓，IPCExecutor.notifyFail 会用 NSLog 兜底
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                NSLog("[rightMenu/MainApp] 通知权限申请失败: %@", error.localizedDescription)
            } else {
                NSLog("[rightMenu/MainApp] 通知权限 granted=%@", granted ? "true" : "false")
            }
        }

        // 首次启动时引导用户启用 Finder 扩展
        let hasShownOnboarding = UserDefaults.standard.bool(forKey: "hasShownFinderExtOnboarding")
        if !hasShownOnboarding {
            showFinderExtensionOnboarding()
            UserDefaults.standard.set(true, forKey: "hasShownFinderExtOnboarding")
        }
    }

    /// 接收来自扩展的 rightmenu:// URL，反序列化后分发给 IPCExecutor。
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let request = IPCRequest.from(url: url) else {
                NSLog("[rightMenu/MainApp] 无法解析 URL: %@", url.absoluteString)
                continue
            }
            NSLog(
                "[rightMenu/MainApp] 收到 IPC: %@, paths=%d",
                request.action.rawValue,
                request.paths.count
            )
            IPCExecutor.execute(request)
        }
    }

    private func showFinderExtensionOnboarding() {
        let alert = NSAlert()
        alert.messageText = "启用 Finder 扩展"
        alert.informativeText = "请前往「系统设置 → 隐私与安全性 → 扩展 → Finder 扩展」，勾选 rightMenu 以启用右键菜单功能。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "前往系统设置")
        alert.addButton(withTitle: "稍后")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            ExtensionsPreferences.open()
        }
    }
}

/// 跳转到「系统设置 → 扩展 → Finder 扩展」面板。
/// 主 App 内的菜单栏入口和首次启动引导都复用此实现，避免分裂。
enum ExtensionsPreferences {
    static func open() {
        // 优先尝试 macOS 13+ 的 Finder 扩展直达 URL
        if let finderExtURL = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences?Finder"),
           NSWorkspace.shared.open(finderExtURL) {
            return
        }
        // 兜底：打开通用扩展偏好面板
        if let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.extensions") {
            NSWorkspace.shared.open(fallback)
        }
    }
}
