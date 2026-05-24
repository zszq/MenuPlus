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
        MenuBarExtra("MenuPlus", systemImage: "filemenu.and.cursorarrow") {
            MenuBarView()
                .environmentObject(runtime)
        }

        Window("MenuPlus 设置", id: "settings") {
            ContentView()
                .environmentObject(runtime)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 460, height: 420)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppRuntime.shared.presentStartupGuidanceIfNeeded()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppRuntime.shared.refreshStatus()
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
}
