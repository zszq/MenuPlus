//
//  ContentView.swift
//  MenuPlus
//
//  Created by l z on 2026/5/12.
//

import SwiftUI
import ServiceManagement
import UserNotifications

struct ContentView: View {
    @EnvironmentObject private var runtime: AppRuntime

    @State private var launchAtLogin: Bool = {
        if #available(macOS 13, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "filemenu.and.cursorarrow")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text("MenuPlus").font(.title).bold()
                    Text("版本 \(Bundle.main.shortVersion)")
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Divider()

            GroupBox("系统状态") {
                VStack(alignment: .leading, spacing: 12) {
                    statusRow(
                        title: "Finder 扩展",
                        value: runtime.isFinderExtensionEnabled ? "已启用" : "未启用",
                        color: runtime.isFinderExtensionEnabled ? .green : .orange,
                        buttonTitle: runtime.isFinderExtensionEnabled ? "重新打开扩展管理…" : "立即启用…"
                    ) {
                        runtime.openFinderExtensionManagement()
                    }

                    statusRow(
                        title: "通知权限",
                        value: notificationStatusText(runtime.notificationStatus),
                        color: notificationStatusColor(runtime.notificationStatus),
                        buttonTitle: runtime.notificationStatus == .authorized ? "打开通知设置" : "授权通知…"
                    ) {
                        if runtime.notificationStatus == .authorized {
                            SystemSettingsNavigator.openNotificationsPrivacy()
                        } else {
                            runtime.requestNotificationAuthorization()
                        }
                    }

                    statusRow(
                        title: "当前运行位置",
                        value: runtime.bundleLocationSummary,
                        color: runtime.bundleInstallState == .applications ? .green : .orange,
                        buttonTitle: "显示当前 App…"
                    ) {
                        runtime.revealCurrentAppInFinder()
                    }
                }
                .padding(8)
            }

            GroupBox("Finder 右键菜单") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("MenuPlus 是 Finder Sync Extension，不会出现在“登录项与扩展 → 文件提供程序”里；请前往“隐私与安全性 → 扩展 → Finder 扩展”启用。")
                        .foregroundColor(.secondary)
                    Text("MenuPlus 使用 Finder Sync Extension 提供右键菜单。首次安装、切换构建产物路径，或从 Xcode 直接调试后，通常都需要重新确认扩展启用状态。")
                        .foregroundColor(.secondary)
                    Text(runtime.bundleLocationGuidanceText)
                        .foregroundColor(runtime.bundleInstallState == .applications ? .secondary : .orange)
                    Text("在 Finder 空白区域执行“新建文件 / 新建 txt 文件”时，MenuPlus 会弹出目录授权面板；请直接选中当前目录本身，后续会自动复用这次授权。")
                        .foregroundColor(.secondary)
                    Text("“在新窗口打开”这类需要控制 Finder 的动作，会在首次使用时触发系统自动化授权；如果你曾拒绝，请到“系统设置 → 隐私与安全性 → 自动化”重新勾选 MenuPlus。")
                        .foregroundColor(.secondary)

                    HStack {
                        Button("打开扩展管理…") {
                            runtime.openFinderExtensionManagement()
                        }
                        Button("打开应用程序文件夹…") {
                            runtime.openApplicationsFolder()
                        }
                        Button("刷新状态") {
                            runtime.refreshStatus()
                        }
                    }
                }
                .padding(8)
            }

            GroupBox("通用") {
                Toggle("开机启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        guard #available(macOS 13, *) else { return }
                        do {
                            if newValue { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        } catch {
                            launchAtLogin = !newValue
                        }
                    }
                    .padding(8)
            }

            Spacer()
        }
        .padding(24)
        .frame(minWidth: 440, minHeight: 380)
        .onAppear {
            runtime.refreshStatus()
        }
    }

    private func statusRow(
        title: String,
        value: String,
        color: Color,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(value)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(buttonTitle, action: action)
        }
    }

    private func notificationStatusText(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized, .provisional:
            return "已授权"
        case .denied:
            return "已拒绝"
        case .notDetermined:
            return "未决定"
        @unknown default:
            return "未知"
        }
    }

    private func notificationStatusColor(_ status: UNAuthorizationStatus) -> Color {
        switch status {
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
}

extension Bundle {
    var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
