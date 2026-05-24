//
//  MenuBarView.swift
//  MenuPlus
//
//  菜单栏下拉菜单内容
//

import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var runtime: AppRuntime

    var body: some View {
        Group {
            if !runtime.isFinderExtensionEnabled {
                Button("启用 Finder 扩展…") {
                    runtime.openFinderExtensionManagement()
                }
            }

            Button("设置…") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }

            Button("退出 MenuPlus") {
                NSApplication.shared.terminate(nil)
            }
        }
        .onAppear {
            runtime.refreshStatus()
        }
    }
}
