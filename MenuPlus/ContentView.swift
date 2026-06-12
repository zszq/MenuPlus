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
    case openWith
}

struct ContentView: View {
    @EnvironmentObject private var runtime: AppRuntime

    @State private var launchAtLogin: Bool = {
        if #available(macOS 13, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }()
    @State private var selectedTab: SettingsTab = .general
    @State private var selectedAuthorizedDirectories = Set<String>()
    @State private var selectedOpenWithAppPaths = Set<String>()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TabView(selection: $selectedTab) {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 20) {
                        settingsHeader()

                        GroupBox("通用") {
                            VStack(alignment: .leading, spacing: 12) {
                                menuBarIconRow()

                                launchAtLoginRow()

                                statusRow(
                                    title: "Finder 扩展",
                                    value: runtime.isFinderExtensionEnabled ? "已启用" : "未启用",
                                    color: runtime.isFinderExtensionEnabled ? .green : .orange,
                                    buttonTitle: "打开扩展设置"
                                ) {
                                    runtime.openFinderExtensionManagement()
                                }

                                statusRow(
                                    title: "通知权限",
                                    value: notificationStatusText(runtime.notificationStatus),
                                    color: notificationStatusColor(runtime.notificationStatus),
                                    buttonTitle: notificationButtonTitle(runtime.notificationStatus)
                                ) {
                                    if runtime.notificationStatus == .notDetermined {
                                        runtime.requestNotificationAuthorization()
                                    } else {
                                        SystemSettingsNavigator.openNotificationsPrivacy()
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
                                .font(.body)
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

                ManagedListTab(
                    title: "目录授权",
                    description: "添加常用目录根目录，这些目录及其所有子目录都会直接复用授权，避免多次触发授权。",
                    addButtonTitle: "添加授权目录…",
                    addAction: { runtime.authorizeDirectoriesFromSettings() },
                    removeButtonTitle: "移除所选授权",
                    removeAction: { runtime.removeAuthorizedDirectories($0) },
                    refreshButtonTitle: "刷新列表",
                    refreshAction: { runtime.refreshAuthorizedDirectories() },
                    emptyText: "暂未保存任何目录授权。",
                    items: runtime.authorizedDirectoryPaths,
                    itemID: \.self,
                    selection: $selectedAuthorizedDirectories
                ) { path in
                    Text(path)
                        .textSelection(.enabled)
                }
                .tabItem {
                    Label("目录授权", systemImage: "folder.badge.gearshape")
                }
                .tag(SettingsTab.directoryAuthorization)

                ManagedListTab(
                    title: "打开方式",
                    description: "添加应用后，右键菜单的 MenuPlus 子菜单中会出现“用 XX 打开”，可对选中的文件或文件夹使用。",
                    addButtonTitle: "添加应用…",
                    addAction: { runtime.addOpenWithAppsFromSettings() },
                    removeButtonTitle: "移除所选",
                    removeAction: { runtime.removeOpenWithApps($0) },
                    emptyText: "暂未添加任何打开方式。",
                    items: runtime.openWithApps,
                    itemID: \.path,
                    selection: $selectedOpenWithAppPaths
                ) { app in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name)
                        Text(app.path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .tabItem {
                    Label("打开方式", systemImage: "arrow.up.forward.app")
                }
                .tag(SettingsTab.openWith)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
        .frame(minWidth: 620, minHeight: 520)
        .onAppear {
            refreshLaunchAtLoginState()
            runtime.refreshStatus()
        }
    }

    private func settingsHeader() -> some View {
        HStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .renderingMode(.original)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: Color.black.opacity(0.16), radius: 8, y: 3)

            VStack(alignment: .leading, spacing: 4) {
                Text("MenuPlus")
                    .font(.title2.bold())
                Text("版本 \(Bundle.main.shortVersion)")
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }

    private func menuBarIconRow() -> some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(runtime.showsMenuBarIcon ? Color.green : Color.orange)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text("菜单栏图标")
                    .font(.headline)
                Text(runtime.showsMenuBarIcon ? "已显示" : "已隐藏")
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { runtime.showsMenuBarIcon },
                set: { runtime.setShowsMenuBarIcon($0) }
            ))
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }

    private func launchAtLoginRow() -> some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(launchAtLogin ? Color.green : Color.orange)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text("开机启动")
                    .font(.headline)
                Text(launchAtLogin ? "已开启" : "未开启")
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { launchAtLogin },
                set: { setLaunchAtLogin($0) }
            ))
                .labelsHidden()
                .toggleStyle(.switch)
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

    private func notificationButtonTitle(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "授权通知…"
        default:
            return "打开通知设置"
        }
    }

    private func refreshLaunchAtLoginState() {
        guard #available(macOS 13, *) else {
            launchAtLogin = false
            return
        }

        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func setLaunchAtLogin(_ isEnabled: Bool) {
        guard #available(macOS 13, *) else {
            launchAtLogin = false
            return
        }

        do {
            if isEnabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLaunchAtLoginState()
        } catch {
            launchAtLogin = !isEnabled
        }
    }
}

/// 设置页"受管列表" Tab 的通用骨架：GroupBox + 说明文字 + 添加/移除（可选刷新）按钮 +
/// 空态文案 / 多选 List。「目录授权」「打开方式」两个 Tab 结构完全一致，
/// 收敛到这里避免后续改样式/交互时两处漂移。
/// 选中项以 String（itemID 取值）标识，与两个调用方的 Set<String> selection 对齐。
private struct ManagedListTab<Item: Equatable, RowContent: View>: View {
    let title: String
    let description: String
    let addButtonTitle: String
    let addAction: () -> Void
    let removeButtonTitle: String
    /// 参数为当前选中的 itemID 集合（已转为数组）
    let removeAction: ([String]) -> Void
    /// 刷新按钮可选：目录授权需要（bookmark 可能被运行时授权链路改动），打开方式不需要
    var refreshButtonTitle: String? = nil
    var refreshAction: (() -> Void)? = nil
    let emptyText: String
    let items: [Item]
    let itemID: KeyPath<Item, String>
    @Binding var selection: Set<String>
    @ViewBuilder let rowContent: (Item) -> RowContent

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox(title) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(description)
                        .foregroundColor(.secondary)

                    HStack {
                        Button(addButtonTitle, action: addAction)
                        Button(removeButtonTitle) {
                            removeAction(Array(selection))
                            selection.removeAll()
                        }
                        .disabled(selection.isEmpty)

                        if let refreshButtonTitle, let refreshAction {
                            Button(refreshButtonTitle, action: refreshAction)
                        }
                    }

                    if items.isEmpty {
                        Text(emptyText)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    } else {
                        List(items, id: itemID, selection: $selection) { item in
                            rowContent(item)
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
        // 列表刷新后清掉已不存在的选中项，避免"移除所选"误删。
        // onAppear 兜底：TabView 非当前 Tab 不在视图树里，期间发生的列表变更
        // 不会触发 onChange，切回本 Tab 时需补一次清理。
        .onChange(of: items) { newItems in
            selection.formIntersection(Set(newItems.map { $0[keyPath: itemID] }))
        }
        .onAppear {
            selection.formIntersection(Set(items.map { $0[keyPath: itemID] }))
        }
    }
}

extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
}
