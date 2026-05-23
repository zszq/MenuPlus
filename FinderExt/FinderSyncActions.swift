//
//  FinderSyncActions.swift
//  FinderExt
//
//  各菜单动作的具体实现逻辑。
//
//  注意：FinderSync 运行在 LSPlugInKitProxy 进程内，系统禁止在此进程中
//  使用 UNUserNotificationCenter（会抛 NSInternalInconsistencyException
//  导致 appex 崩溃）。因此本文件所有错误反馈一律走 NSLog，不要再引入任何
//  用户通知 API。
//

import Cocoa

enum FinderSyncActions {

    // MARK: - 动作 1：在终端中打开（仅文件夹）

    static func openInTerminal(url: URL) {
        // 为 AppleScript 双引号字符串转义反斜杠和双引号；
        // 单引号被 shell 包裹，需用 '\'' 序列转义。
        let escapedForAppleScript = url.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let escapedForShell = escapedForAppleScript
            .replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        tell application "Terminal"
            activate
            do script "cd '\(escapedForShell)'"
        end tell
        """
        guard let appleScript = NSAppleScript(source: script) else {
            NSLog("[rightMenu] 打开终端: 无法创建 AppleScript 对象")
            return
        }
        var errorDict: NSDictionary?
        appleScript.executeAndReturnError(&errorDict)
        if let error = errorDict {
            NSLog("[rightMenu] 打开终端失败: %@（请确认已授予 rightMenu 控制 Terminal 的权限：系统设置 → 隐私与安全性 → 自动化）", String(describing: error))
        }
    }

    // MARK: - 动作 2：在 VSCode 中打开

    static func openInVSCode(url: URL) {
        // 先检测 VSCode 是否安装（通过 NSWorkspace 查询能否处理 vscode:// scheme）
        guard let checkURL = URL(string: "vscode://") else { return }
        let canOpen = NSWorkspace.shared.urlForApplication(toOpen: checkURL) != nil

        guard canOpen else {
            NSLog("[rightMenu] 打开 VSCode 失败: 未找到 VSCode，请确认已安装 Visual Studio Code 并已注册 vscode:// URL scheme")
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

        baseName = "新建文件"
        if let ext = fileExtension, !ext.isEmpty {
            suffix = ".\(ext)"
        } else {
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

        let created = fileManager.createFile(atPath: targetURL.path, contents: nil, attributes: nil)
        if !created {
            NSLog("[rightMenu] 新建文件失败: 无法在 %@ 创建文件 %@，可能没有写入权限", directory.path, targetURL.lastPathComponent)
        }
    }

    // MARK: - 动作 8：在新 Finder 窗口中打开

    /// 在新的 Finder 窗口中打开指定文件夹。
    static func openInNewFinderWindow(url: URL) {
        // NSWorkspace.open(_:) 默认会让 Finder 在新窗口中显示该目录
        NSWorkspace.shared.open(url)
    }
}
