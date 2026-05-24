//
//  MenuBarView.swift
//  MenuPlus
//
//  菜单栏下拉菜单内容
//

import SwiftUI
import UserNotifications

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var runtime: AppRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusLine(
                title: "Finder 扩展",
                value: runtime.isFinderExtensionEnabled ? "已启用" : "未启用",
                color: runtime.isFinderExtensionEnabled ? .green : .orange
            )

            statusLine(
                title: "通知",
                value: notificationSummary,
                color: notificationColor
            )
        }
        .padding(.bottom, 4)

        Divider()

        if !runtime.isFinderExtensionEnabled {
            Button("启用 Finder 扩展…") {
                runtime.openFinderExtensionManagement()
            }
        }

        Button("刷新状态") {
            runtime.refreshStatus()
        }

        Button("设置…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "settings")
        }

        Divider()

        Button("退出 MenuPlus") {
            NSApplication.shared.terminate(nil)
        }
        .onAppear {
            runtime.refreshStatus()
        }
    }

    private var notificationSummary: String {
        switch runtime.notificationStatus {
        case .authorized, .provisional:
            return "已授权"
        case .notDetermined:
            return "未决定"
        case .denied:
            return "已拒绝"
        @unknown default:
            return "未知"
        }
    }

    private var notificationColor: Color {
        switch runtime.notificationStatus {
        case .authorized, .provisional:
            return .green
        case .notDetermined:
            return .orange
        case .denied:
            return .red
        @unknown default:
            return .gray
        }
    }

    private func statusLine(title: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}
