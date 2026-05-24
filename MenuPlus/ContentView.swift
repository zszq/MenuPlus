//
//  ContentView.swift
//  MenuPlus
//
//  Created by l z on 2026/5/12.
//

import SwiftUI
import ServiceManagement
import AppKit

struct ContentView: View {
    @State private var launchAtLogin: Bool = {
        if #available(macOS 13, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "filemenu.and.cursorarrow")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading) {
                    Text("MenuPlus").font(.title).bold()
                    Text("版本 \(Bundle.main.shortVersion)")
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Divider()

            // Finder Extension section
            GroupBox("Finder 扩展") {
                HStack {
                    Text("在访达右键菜单中提供快捷操作")
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("打开扩展设置…") {
                        ExtensionsPreferences.open()
                    }
                }
                .padding(4)
            }

            // General section
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
                    .padding(4)
            }

            Spacer()
        }
        .padding(24)
        .frame(minWidth: 380, minHeight: 280)
    }
}

extension Bundle {
    var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

#Preview {
    ContentView()
}
