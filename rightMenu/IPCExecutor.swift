//
//  IPCExecutor.swift
//  rightMenu
//
//  主 App 端 IPC 动作执行器（无 sandbox 环境）。
//  扩展进程因 sandbox 拒绝的写操作（创建文件、唤起外部进程等），
//  都通过 rightmenu:// URL 转交给这里执行。
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

        case .createBlankFile:
            guard let dir = request.paths.first else {
                return notifyFail("新建文件", "缺少目录")
            }
            createFile(inDirectory: dir, baseName: "新建文件", extension: nil)

        case .createTxtFile:
            guard let dir = request.paths.first else {
                return notifyFail("新建 txt", "缺少目录")
            }
            createFile(inDirectory: dir, baseName: "新建文件", extension: "txt")

        case .openInNewFinderWindow:
            guard let path = request.paths.first else {
                return notifyFail("新 Finder 窗口", "缺少路径")
            }
            let escapedPath = path.replacingOccurrences(of: "\"", with: "\\\"")
            let src = "tell application \"Finder\" to make new Finder window to (POSIX file \"\(escapedPath)\")"
            guard let script = NSAppleScript(source: src) else {
                return notifyFail("新 Finder 窗口", "脚本初始化失败")
            }
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            if error != nil {
                notifyFail("新 Finder 窗口", "无法打开 \(path)")
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

    /// 在指定目录创建空白文件。冲突时自动加数字后缀。
    private static func createFile(inDirectory dir: String, baseName: String, extension ext: String?) {
        let dirURL = URL(fileURLWithPath: dir)
        let suffix = ext.map { ".\($0)" } ?? ""
        var name = "\(baseName)\(suffix)"
        var idx = 2
        while FileManager.default.fileExists(atPath: dirURL.appendingPathComponent(name).path) {
            name = "\(baseName) \(idx)\(suffix)"
            idx += 1
        }
        let fileURL = dirURL.appendingPathComponent(name)
        if !FileManager.default.createFile(atPath: fileURL.path, contents: nil) {
            notifyFail("新建文件", "无法在 \(dir) 创建 \(name)")
        }
    }

    // MARK: - 失败反馈

    private static func notifyFail(_ action: String, _ reason: String) {
        NSLog("[rightMenu/MainApp] 执行失败: %@ - %@", action, reason)
        let content = UNMutableNotificationContent()
        content.title = "rightMenu — \(action)失败"
        content.body = reason
        let req = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req) { error in
            if let error = error {
                NSLog("[rightMenu/MainApp] 通知投递失败: %@", error.localizedDescription)
            }
        }
    }
}
