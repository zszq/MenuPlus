//
//  MenuPlusApp.swift
//  MenuPlus
//
//  Created by l z on 2026/5/12.
//

import SwiftUI
import AppKit

@main
struct MenuPlusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var runtime = AppRuntime.shared

    var body: some Scene {
        MenuBarExtra(
            "MenuPlus",
            systemImage: "filemenu.and.cursorarrow",
            isInserted: Binding(
                get: { runtime.showsMenuBarIcon },
                set: { runtime.setShowsMenuBarIcon($0) }
            )
        ) {
            MenuBarView()
                .environmentObject(runtime)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    private var settingsWindowController: SettingsWindowController?

    override init() {
        super.init()
        Self.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 启动即镜像写一次共享配置 JSON：覆盖旧版本升级 / 容器被清的场景，
        // 否则 Finder 扩展会一直读不到配置而不显示"用 XX 打开"菜单项
        OpenWithAppStore.mirrorToSharedConfigFile()

        if AppRuntime.shared.showsMenuBarIcon {
            AppRuntime.shared.presentStartupGuidanceIfNeeded()
        } else {
            showSettingsWindow()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppRuntime.shared.refreshStatus()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettingsWindow()
        return false
    }

    /// 接收来自扩展的 menuplus:// URL，反序列化后分发给 IPCExecutor。
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let request = IPCRequest.from(url: url) else {
                NSLog("[MenuPlus/MainApp] 无法解析 URL: %@", url.absoluteString)
                continue
            }
            NSLog(
                "[MenuPlus/MainApp] 收到 IPC: %@, paths=%d",
                request.action.rawValue,
                request.paths.count
            )
            IPCExecutor.execute(request)
        }
    }

    func showSettingsWindow() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(runtime: AppRuntime.shared)
        }

        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        settingsWindowController?.window?.orderFrontRegardless()
    }
}

final class SettingsWindowController: NSWindowController {
    init(runtime: AppRuntime) {
        let rootView = ContentView()
            .environmentObject(runtime)
            .frame(minWidth: 620, minHeight: 520)

        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "MenuPlus 设置"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 780, height: 680))
        window.contentMinSize = NSSize(width: 620, height: 520)
        window.center()
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed

        super.init(window: window)
        shouldCascadeWindows = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
