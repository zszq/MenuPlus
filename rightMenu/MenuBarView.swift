//
//  MenuBarView.swift
//  rightMenu
//
//  菜单栏下拉菜单内容
//

import SwiftUI
import ServiceManagement

struct MenuBarView: View {
    @State private var launchAtLogin: Bool = {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }()

    var body: some View {
        // 启用 Finder 扩展
        Button("启用 Finder 扩展…") {
            openExtensionsPreferences()
        }

        Divider()

        // 开机启动开关
        Toggle("开机启动", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { newValue in
                toggleLaunchAtLogin(newValue)
            }

        Divider()

        // 退出
        Button("退出 rightMenu") {
            NSApplication.shared.terminate(nil)
        }
    }

    private func openExtensionsPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.extensions") {
            NSWorkspace.shared.open(url)
        }
    }

    private func toggleLaunchAtLogin(_ enable: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enable {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("SMAppService error: \(error)")
            }
        }
    }
}
