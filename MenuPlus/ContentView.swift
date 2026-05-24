//
//  ContentView.swift
//  MenuPlus
//
//  Created by l z on 2026/5/12.
//

import SwiftUI
import ServiceManagement
import UserNotifications

private enum SettingsTab: Hashable {
    case general
    case directoryAuthorization
}

struct ContentView: View {
    @EnvironmentObject private var runtime: AppRuntime

    @State private var launchAtLogin: Bool = {
        if #available(macOS 13, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }()
    @State private var selectedTab: SettingsTab = .general
    @State private var selectedAuthorizedDirectories = Set<String>()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TabView(selection: $selectedTab) {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 20) {
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

                        HStack {
                            Spacer()
                            Text("版本 \(Bundle.main.shortVersion)")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                }
                .tabItem {
                    Label("基础设置", systemImage: "slider.horizontal.3")
                }
                .tag(SettingsTab.general)

                VStack(alignment: .leading, spacing: 20) {
                    GroupBox("目录授权") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("添加常用目录根目录，这些目录及其所有子目录都会直接复用授权，避免多次触发授权。")
                                .foregroundColor(.secondary)

                            HStack {
                                Button("添加授权目录…") {
                                    runtime.authorizeDirectoriesFromSettings()
                                }
                                Button("移除所选授权") {
                                    runtime.removeAuthorizedDirectories(Array(selectedAuthorizedDirectories))
                                    selectedAuthorizedDirectories.removeAll()
                                }
                                .disabled(selectedAuthorizedDirectories.isEmpty)

                                Button("刷新列表") {
                                    runtime.refreshAuthorizedDirectories()
                                }
                            }

                            if runtime.authorizedDirectoryPaths.isEmpty {
                                Text("暂未保存任何目录授权。")
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 8)
                            } else {
                                List(runtime.authorizedDirectoryPaths, id: \.self, selection: $selectedAuthorizedDirectories) { path in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(path)
                                            .textSelection(.enabled)
                                        Text("该目录下的所有子目录都会复用这次授权")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 2)
                                }
                                .frame(minHeight: 320)
                            }
                        }
                        .padding(8)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(20)
                .tabItem {
                    Label("目录授权", systemImage: "folder.badge.gearshape")
                }
                .tag(SettingsTab.directoryAuthorization)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
        .frame(minWidth: 620, minHeight: 520)
        .onAppear {
            runtime.refreshStatus()
        }
        .onChange(of: runtime.authorizedDirectoryPaths) { newPaths in
            selectedAuthorizedDirectories.formIntersection(Set(newPaths))
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
