//
//  IPCExecutor.swift
//  MenuPlus
//
//  主 App 端 IPC 动作执行器。
//  需要在主 App 进程执行的动作（如控制 Terminal、控制 Finder AppleScript）
//  通过 menuplus:// URL 转交给这里执行。
//  文件创建操作已移至 FinderExt/FinderSyncActions，由扩展进程直接执行。
//

import AppKit
import UserNotifications

enum IPCExecutor {
    static func execute(_ request: IPCRequest) {
        switch request.action {
        case .openInTerminal:
            guard let path = request.paths.first else {
                return notifyFail("在终端打开", "缺少目标路径")
            }
            openInTerminal(path: path)

        case .openInNewFinderWindow:
            guard let path = request.paths.first else {
                return notifyFail("新 Finder 窗口", "缺少路径")
            }
            let escapedPath = path
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
            let src = "tell application \"Finder\" to make new Finder window to (POSIX file \"\(escapedPath)\")"
            guard let script = NSAppleScript(source: src) else {
                return notifyFail("新 Finder 窗口", "脚本初始化失败")
            }
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            if error != nil {
                return notifyFail("新 Finder 窗口", "无法打开 \(path)")
            }
        }
    }

    // MARK: - 具体动作

    private static func openInTerminal(path: String) {
        let terminalURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(
            [URL(fileURLWithPath: path)],
            withApplicationAt: terminalURL,
            configuration: config
        ) { _, error in
            if let error = error {
                notifyFail("在终端打开", error.localizedDescription)
            }
        }
    }

    // MARK: - 失败反馈

    private static func notifyFail(_ action: String, _ reason: String) {
        NSLog("[MenuPlus/MainApp] 执行失败: %@ - %@", action, reason)
        let content = UNMutableNotificationContent()
        content.title = "MenuPlus — \(action)失败"
        content.body = reason
        let req = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req) { error in
            if let error = error {
                NSLog("[MenuPlus/MainApp] 通知投递失败: %@", error.localizedDescription)
            }
        }
    }
}
