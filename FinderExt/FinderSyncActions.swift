//
//  FinderSyncActions.swift
//  FinderExt
//
//  扩展进程内直接执行的菜单动作（不受 sandbox 限制的部分）。
//
//  目前仅保留：
//    - 在 VSCode 中打开（vscode:// 走 LaunchServices 同源 scheme，扩展可用）
//    - 复制完整路径 / 文件名（NSPasteboard 在扩展内可用）
//
//  其余受 sandbox 限制的动作（在终端打开 / 空白区域新建文件 / 新 Finder 窗口）
//  已通过 IPCClient 转发给主 App 由 IPCExecutor 执行。
//
//  注意：FinderSync 运行在 LSPlugInKitProxy 进程内，系统禁止在此进程中
//  使用 UNUserNotificationCenter（会抛 NSInternalInconsistencyException
//  导致 appex 崩溃）。因此本文件所有错误反馈一律走 NSLog，不要再引入任何
//  用户通知 API。
//

import Cocoa

enum FinderSyncActions {

    // MARK: - 动作 2：在 VSCode 中打开

    static func openInVSCode(url: URL) {
        // 先检测 VSCode 是否安装（通过 NSWorkspace 查询能否处理 vscode:// scheme）
        guard let checkURL = URL(string: "vscode://") else { return }
        let canOpen = NSWorkspace.shared.urlForApplication(toOpen: checkURL) != nil

        guard canOpen else {
            NSLog("[MenuPlus] 打开 VSCode 失败: 未找到 VSCode，请确认已安装 Visual Studio Code 并已注册 vscode:// URL scheme")
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

    // MARK: - 动作 3 / 4：复制到剪贴板

    static func copyToClipboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    // MARK: - 动作 5 / 6：对“明确选中的文件夹”直接创建文件

    /// 在指定目录创建空白文件。冲突时自动加数字后缀（例如"新建文件 2"）。
    /// FinderExt 持有 com.apple.security.files.user-selected.read-write entitlement，
    /// 对用户右键选中的文件夹拥有写权限，无需走 IPC。
    /// 若是右键 Finder 空白区域，当前目录不属于 user-selected 资源，必须转给主 App
    /// 走 security-scoped bookmark 授权后再创建。
    static func createFile(inDirectory dir: String, baseName: String, extension ext: String?) {
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
            NSLog("[MenuPlus/FinderExt] 新建文件失败：无法在 %@ 创建 %@", dir, name)
        }
    }
}
