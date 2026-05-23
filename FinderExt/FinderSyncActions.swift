//
//  FinderSyncActions.swift
//  FinderExt
//
//  各菜单动作的具体实现逻辑。
//

import Cocoa
import UserNotifications

enum FinderSyncActions {

    // MARK: - 动作 1：在终端中打开（仅文件夹）

    static func openInTerminal(url: URL) {
        // 对路径中的单引号进行转义，防止 AppleScript 注入
        let safePath = url.path.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        tell application "Terminal"
            activate
            do script "cd '\(safePath)'"
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var errorDict: NSDictionary?
            appleScript.executeAndReturnError(&errorDict)
            if let error = errorDict {
                print("AppleScript error: \(error)")
            }
        }
    }

    // MARK: - 动作 2：在 VSCode 中打开

    static func openInVSCode(url: URL) {
        // 先检测 VSCode 是否安装（通过 NSWorkspace 查询能否处理 vscode:// scheme）
        guard let checkURL = URL(string: "vscode://") else { return }
        let canOpen = NSWorkspace.shared.urlForApplication(toOpen: checkURL) != nil

        guard canOpen else {
            sendNotification(
                title: "未找到 VSCode",
                body: "请确认已安装 Visual Studio Code 并已注册 vscode:// URL scheme。"
            )
            return
        }

        // 构建 vscode://file//<path> URL
        // path 需要以 "/" 开头使其变成 "//absolute-path"，
        // 这样 URLComponents 才能正确生成 vscode://file//Users/foo/bar
        var components = URLComponents()
        components.scheme = "vscode"
        components.host = "file"
        components.path = "/" + url.path   // url.path 已是 /xxx，结果为 //xxx
        guard let vscodeURL = components.url else { return }
        NSWorkspace.shared.open(vscodeURL)
    }

    // MARK: - 动作 3：复制完整路径

    static func copyToClipboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    // MARK: - 动作 5 & 6：新建文件

    /// 在指定目录创建空白文件。
    /// - Parameters:
    ///   - directory: 目标文件夹 URL
    ///   - extension: 文件扩展名（nil 表示无扩展名的空白文件）
    static func createBlankFile(inDirectory directory: URL, extension fileExtension: String?) {
        let baseName: String
        let suffix: String

        if let ext = fileExtension {
            baseName = "新建文本文件"
            suffix = ".\(ext)"
        } else {
            baseName = "新建文件"
            suffix = ""
        }

        let fileManager = FileManager.default
        var targetURL = directory.appendingPathComponent("\(baseName)\(suffix)")

        // 冲突时自动加数字后缀
        var counter = 2
        while fileManager.fileExists(atPath: targetURL.path) {
            targetURL = directory.appendingPathComponent("\(baseName) \(counter)\(suffix)")
            counter += 1
        }

        fileManager.createFile(atPath: targetURL.path, contents: nil, attributes: nil)
    }

    // MARK: - 动作 7：显示/隐藏隐藏文件

    /// 读取当前 Finder 隐藏文件显示状态。
    static func hiddenFilesVisible() -> Bool {
        let defaults = UserDefaults(suiteName: "com.apple.finder")
        return defaults?.bool(forKey: "AppleShowAllFiles") ?? false
    }

    /// 切换 Finder 隐藏文件显示状态，并重启 Finder 使其生效。
    static func toggleHiddenFiles() {
        let currentValue = hiddenFilesVisible()
        let newValue = !currentValue

        // 写入 Finder 偏好设置
        let defaults = UserDefaults(suiteName: "com.apple.finder")
        defaults?.set(newValue, forKey: "AppleShowAllFiles")
        defaults?.synchronize()

        // 重启 Finder
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Finder"]
        try? process.run()
    }

    // MARK: - 辅助：发送用户通知

    private static func sendNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }
}
