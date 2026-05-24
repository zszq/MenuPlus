//
//  MenuBarView.swift
//  MenuPlus
//
//  菜单栏下拉菜单内容
//

import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("设置…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "settings")
        }

        Divider()

        Button("退出 MenuPlus") {
            NSApplication.shared.terminate(nil)
        }
    }
}
