//
//  MenuBarView.swift
//  rightMenu
//
//  菜单栏下拉菜单内容
//

import SwiftUI
import ServiceManagement
import AppKit

struct MenuBarView: View {
    /// 当前开机启动状态。直接读取 SMAppService 的实时状态作为默认值；
    /// 用户切换时再写入 SMAppService 并刷新本地状态。
    @State private var launchAtLogin: Bool = currentLaunchAtLoginEnabled()

    var body: some View {
        // 启用 Finder 扩展
        Button("打开 Finder 扩展设置…") {
            ExtensionsPreferences.open()
        }

        Divider()

        // 开机启动开关
        // 用 Binding 包装直接拦截写入，避免 onChange API 在 macOS 13/14 之间的签名差异。
        Toggle("开机启动", isOn: Binding(
            get: { launchAtLogin },
            set: { toggleLaunchAtLogin($0) }
        ))

        Divider()

        // 退出
        Button("退出 rightMenu") {
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - 行为

    /// 切换开机启动状态，失败时回滚 UI 状态。
    private func toggleLaunchAtLogin(_ enable: Bool) {
        guard #available(macOS 13.0, *) else {
            // macOS 13 以下不支持，不修改本地状态
            return
        }
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            // 写入后根据系统真实状态校正本地值，避免 UI 与系统不一致
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch {
            NSLog("SMAppService 切换失败: %@", String(describing: error))
            // 失败回滚到操作前的状态
            launchAtLogin = !enable
        }
    }
}

/// 读取当前开机启动是否启用（包级辅助函数）。
private func currentLaunchAtLoginEnabled() -> Bool {
    if #available(macOS 13.0, *) {
        return SMAppService.mainApp.status == .enabled
    }
    return false
}
