//
//  OpenWithAppStore.swift
//  MenuPlus
//
//  "用 XX 打开" 应用列表的持久化与跨进程共享。
//  数据源放 UserDefaults（主 App 内部读写最简单）；每次变更后同步镜像写一份
//  JSON 到真实 home 的 ~/Library/Application Support/MenuPlus/，凭
//  temporary-exception entitlement 写入，供 FinderSync 扩展只读
//  （ad-hoc 签名下无 App Group，方案说明见 IPCAction.swift 的 ExtensionSharedConfig 注释）。
//

import AppKit

enum OpenWithAppStore {
    private static let defaultsKey = "openWithApps"

    static func apps() -> [OpenWithApp] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            return []
        }

        do {
            return try JSONDecoder().decode([OpenWithApp].self, from: data)
        } catch {
            NSLog("[MenuPlus/MainApp] 解码 openWithApps 失败: %@", error.localizedDescription)
            return []
        }
    }

    /// 添加一个 .app，按标准化后的 path 去重（同一 App 重复添加会产生重复菜单项）。
    static func add(url: URL) {
        let standardizedPath = url.standardizedFileURL.path
        var current = apps()
        guard !current.contains(where: { $0.path == standardizedPath }) else {
            return
        }

        current.append(OpenWithApp(name: displayName(for: url), path: standardizedPath))
        persist(current)
    }

    static func remove(paths: [String]) {
        guard !paths.isEmpty else {
            return
        }

        let removal = Set(paths)
        persist(apps().filter { !removal.contains($0.path) })
    }

    /// App 启动时调用一次：保证镜像 JSON 存在。
    /// 覆盖"旧版本升级到本版本 / 容器被清理但 UserDefaults 仍在"等场景，
    /// 否则扩展会一直读不到配置文件。
    static func mirrorToSharedConfigFile() {
        writeSharedConfig(apps: apps())
    }

    // MARK: - 私有

    /// 菜单显示名优先取 bundle 声明的显示名（与 Finder 显示一致），兜底用文件名去 .app 后缀。
    private static func displayName(for url: URL) -> String {
        if let bundle = Bundle(url: url) {
            if let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
               !displayName.isEmpty {
                return displayName
            }
            if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
               !name.isEmpty {
                return name
            }
        }
        return url.deletingPathExtension().lastPathComponent
    }

    private static func persist(_ apps: [OpenWithApp]) {
        do {
            let data = try JSONEncoder().encode(apps)
            UserDefaults.standard.set(data, forKey: defaultsKey)
        } catch {
            NSLog("[MenuPlus/MainApp] 编码 openWithApps 失败: %@", error.localizedDescription)
        }

        // UserDefaults 与共享 JSON 必须同步更新，否则扩展菜单与设置页内容不一致
        writeSharedConfig(apps: apps)
    }

    /// 镜像写共享 JSON。写失败只记日志不崩溃：扩展读不到时会自行优雅降级（不显示自定义菜单项）。
    private static func writeSharedConfig(apps: [OpenWithApp]) {
        // 沙盒内 FileManager.urls(for: .applicationSupportDirectory) 和 NSHomeDirectory()
        // 都指向主 App 自己的容器，而扩展读不了别人的容器（系统级保护，实测被拒）。
        // 必须写真实 home 下的中立路径，路径解析统一走契约里的 configFileURL()
        // （内部用 getpwuid 取真实 home，与扩展端读取逻辑天然一致）。
        guard let fileURL = ExtensionSharedConfig.configFileURL() else {
            NSLog("[MenuPlus/MainApp] getpwuid 取真实 home 失败，跳过共享配置写出")
            return
        }
        let directoryURL = fileURL.deletingLastPathComponent()

        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let config = ExtensionSharedConfig(
                version: ExtensionSharedConfig.currentVersion,
                openWithApps: apps
            )
            let data = try JSONEncoder().encode(config)
            try data.write(to: fileURL, options: .atomic)
            NSLog("[MenuPlus/MainApp] 已写出共享配置: %@, apps=%d", fileURL.path, apps.count)
        } catch {
            NSLog("[MenuPlus/MainApp] 写出共享配置失败: %@", error.localizedDescription)
        }
    }
}
