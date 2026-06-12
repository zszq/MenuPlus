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
    /// 损坏数据的备份 key：重置前把原始 Data 原样挪到这里，便于事后排查 / 未来迁移恢复。
    private static let corruptedBackupKey = "openWithApps.corruptedBackup"

    /// 持久层的三态读取结果。
    /// 必须区分"无数据"与"有数据但解码失败"：后者若被当成空列表，
    /// 任意一次 add/remove 就会以空基线 persist，把用户全部配置静默清空。
    private enum LoadResult {
        case empty                  // 从未写过数据，正常空列表
        case loaded([OpenWithApp])  // 解码成功
        case corrupted              // 有数据但解码失败，禁止以空基线覆盖
    }

    private static func load() -> LoadResult {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            return .empty
        }

        do {
            return .loaded(try JSONDecoder().decode([OpenWithApp].self, from: data))
        } catch {
            NSLog("[MenuPlus/MainApp] 解码 openWithApps 失败（数据损坏）: %@", error.localizedDescription)
            return .corrupted
        }
    }

    /// 读路径：损坏时优雅降级返回空列表（设置页 / 扩展菜单显示为空但不崩溃）。
    /// 写路径不允许走这个方法取基线，必须用 load() 区分损坏态。
    static func apps() -> [OpenWithApp] {
        if case .loaded(let apps) = load() {
            return apps
        }
        return []
    }

    /// 批量添加 .app，按标准化后的 path 去重（同一 App 重复添加会产生重复菜单项）。
    /// 刻意收批量而非单个：设置页 NSOpenPanel 允许多选，一次面板确认必须只算
    /// "一次 mutation"——若按单个循环调用，损坏自救的两段式确认会被同一手势内的
    /// 第二次调用直接击穿（用户还没看到提示，数据就被重置了）。
    static func add(urls: [URL]) {
        guard !urls.isEmpty else {
            return
        }
        guard var updated = mutationBaseline(action: "添加打开方式应用") else {
            return
        }

        let countBeforeAppend = updated.count
        for url in urls {
            let standardizedPath = url.standardizedFileURL.path
            guard !updated.contains(where: { $0.path == standardizedPath }) else {
                continue
            }
            updated.append(OpenWithApp(name: displayName(for: url), path: standardizedPath))
        }

        // 全部是重复项时不写：避免无意义的 UserDefaults + 共享 JSON 双写
        guard updated.count != countBeforeAppend else {
            return
        }
        persist(updated)
    }

    static func remove(paths: [String]) {
        guard !paths.isEmpty else {
            return
        }
        // 损坏时设置页列表显示为空、无项可选中，正常 UI 走不到损坏分支；
        // 仍走统一基线入口，保证任何调用方都不会以空基线覆盖损坏数据
        guard let current = mutationBaseline(action: "移除打开方式应用") else {
            return
        }

        let removal = Set(paths)
        persist(current.filter { !removal.contains($0.path) })
    }

    /// App 启动时调用一次：保证镜像 JSON 存在。
    /// 覆盖"旧版本升级到本版本 / 容器被清理但 UserDefaults 仍在"等场景，
    /// 否则扩展会一直读不到配置文件。
    static func mirrorToSharedConfigFile() {
        switch load() {
        case .empty:
            writeSharedConfig(apps: [])
        case .loaded(let apps):
            writeSharedConfig(apps: apps)
        case .corrupted:
            // 损坏时跳过镜像：磁盘上的共享 JSON 可能还是用户上次的完好配置，
            // 把 [] 写出去会让扩展菜单无故消失。保留旧文件，右键菜单至少还能用。
            NSLog("[MenuPlus/MainApp] openWithApps 数据损坏，跳过共享配置镜像写出，保留现有共享 JSON")
        }
    }

    // MARK: - 损坏数据的自救出路

    /// "重置确认"标记，仅进程生命周期内有效，刻意不持久化：
    /// App 重启后回到"先提示再重置"状态，宁可多提示一次，也不在用户无感知时清数据。
    /// 线程契约：仅主线程读写——现有 mutation 入口都来自 @MainActor 的 AppRuntime
    /// （设置页按钮）；新增调用方必须保持主线程调用，否则需补同步。
    private static var corruptedResetConfirmed = false

    /// mutation 的统一基线入口。返回 nil 表示本次 mutation 必须中止（损坏数据尚未确认重置），
    /// 调用方不得 persist 任何内容。
    private static func mutationBaseline(action: String) -> [OpenWithApp]? {
        switch load() {
        case .empty:
            // 数据已不在损坏态（如外部手段修复/清除），作废未消费的重置确认，
            // 避免未来再次损坏时第一次 mutation 跳过提示直接重置
            corruptedResetConfirmed = false
            return []
        case .loaded(let apps):
            corruptedResetConfirmed = false
            return apps
        case .corrupted:
            return resolveCorruptedStorageBeforeMutation(action: action) ? [] : nil
        }
    }

    /// 损坏态下 mutation 的处理。返回 true 表示存储已重置、调用方可以空列表为基线继续。
    ///
    /// 自救出路（两段式确认，避免用户永久卡死）：
    /// 1. 第一次 mutation 撞上损坏数据 → 中止并通知，告知"再次执行添加即可备份并重建"
    /// 2. 用户再次执行任意 mutation → 把损坏的原始 Data 挪到备份 key（不丢数据），
    ///    清掉主 key 后放行，本次操作以空配置为基线正常完成
    private static func resolveCorruptedStorageBeforeMutation(action: String) -> Bool {
        if corruptedResetConfirmed {
            if let data = UserDefaults.standard.data(forKey: defaultsKey) {
                UserDefaults.standard.set(data, forKey: corruptedBackupKey)
            }
            UserDefaults.standard.removeObject(forKey: defaultsKey)
            corruptedResetConfirmed = false
            NSLog("[MenuPlus/MainApp] 已把损坏的 openWithApps 数据备份到 %@ 并重置主存储", corruptedBackupKey)
            return true
        }

        corruptedResetConfirmed = true
        FailurePresenter.present(
            action: action,
            reason: "“打开方式”配置数据已损坏，本次操作已中止。再次执行“添加应用…”将自动备份损坏数据并重建空配置，之后请重新添加所需应用。"
        )
        return false
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
