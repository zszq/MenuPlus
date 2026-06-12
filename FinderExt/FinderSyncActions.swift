//
//  FinderSyncActions.swift
//  FinderExt
//
//  扩展进程内直接执行的菜单动作（不受 sandbox 限制的部分）。
//
//  目前仅保留：
//    - 复制完整路径 / 文件名（NSPasteboard 在扩展内可用）
//
//  其余受 sandbox 限制的动作（在终端打开 / 新建文件 / 新 Finder 窗口 /
//  用自定义应用打开）已通过 IPCClient 转发给主 App 由 IPCExecutor 执行。
//  曾经硬编码的「在 VSCode 中打开」也已迁移到通用"用 XX 打开"机制
//  （主 App 首次启动检测到 VSCode 时自动 seed 进 OpenWithAppStore）。
//
//  注意：FinderSync 运行在 LSPlugInKitProxy 进程内，系统禁止在此进程中
//  使用 UNUserNotificationCenter（会抛 NSInternalInconsistencyException
//  导致 appex 崩溃）。因此本文件所有错误反馈一律走 NSLog，不要再引入任何
//  用户通知 API。
//

import Cocoa

enum FinderSyncActions {

    // MARK: - 复制到剪贴板

    static func copyToClipboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
