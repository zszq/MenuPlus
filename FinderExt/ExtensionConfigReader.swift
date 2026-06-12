//
//  ExtensionConfigReader.swift
//  FinderExt
//
//  读取主 App 镜像写出的共享配置（"用 XX 打开" 应用列表）。
//  文件位于真实 home 的 ~/Library/Application Support/MenuPlus/，
//  扩展凭 temporary-exception 只读 entitlement 访问（方案演进与原因见
//  IPCAction.swift 的 ExtensionSharedConfig 注释及 FinderExt.entitlements）。
//  任何失败都返回空列表（菜单优雅降级），并按原因分别 NSLog，
//  便于部署后用 log show 诊断。
//
//  性能：Finder 右键菜单（menu(for:)）是阻塞 UI 的热路径，不能每次都
//  读盘 + JSON 解码。这里用 mtime+size 指纹做缓存：每次调用只 stat 一次，
//  指纹未变直接复用上次的解码结果；失败态同样缓存，且日志只在状态变化时
//  打一次，避免用户连续右键时刷屏。
//

import Foundation

enum ExtensionConfigReader {

    /// 文件指纹：mtime + size 任一变化即视为内容已变，需要重读。
    /// 单次 attributesOfItem（一次 stat）可同时拿到两个值，开销远低于读盘 + 解码。
    ///
    /// 已知边界：理论上文件被原子替换为"size 相同且 mtime 落在同一时间戳"的新内容时
    /// 会误命中缓存。实际风险可忽略：APFS 的 mtime 为纳秒级精度（Foundation 的 Date
    /// 保留亚秒部分），且主 App 的 .atomic 写入是"新文件替换"（新 inode、新 mtime）；
    /// 即便极端撞上，后果也只是一次右键菜单显示旧列表，下次写入即恢复。
    private struct Fingerprint: Equatable {
        let modificationDate: Date
        let fileSize: UInt64
    }

    /// 缓存上一次的读取结果（成功与失败态都缓存）。
    ///
    /// 为什么不加锁：load() 仅被 FinderSync.init()（启动诊断日志，单次）与
    /// menu(for:)（Finder 对同一实例串行调用，主线程逐次进入）调用，
    /// init 必然先于任何 menu(for:) 完成，不存在并发读写本缓存的路径，
    /// 加锁只会增加热路径开销，故刻意不加。若未来出现其他调用线程，必须补同步。
    ///
    /// cachedFingerprint == nil 表示上次失败在 stat 之前（文件不存在 / 无法定位），
    /// 此时每次都会重新 stat（开销极小），文件一旦出现即可恢复。
    private static var cachedFingerprint: Fingerprint?
    private static var cachedApps: [OpenWithApp] = []
    private static var hasCache = false
    /// 上一次打过的日志内容；内容相同视为状态未变，不重复打。
    private static var lastLoggedState: String?

    /// 读取自定义"用 XX 打开"应用列表；任何失败返回 []（调用方据此隐藏自定义菜单项）。
    static func load() -> [OpenWithApp] {
        // 路径解析统一走契约里的 configFileURL()（getpwuid 取真实 home），与主 App 写出逻辑一致
        guard let fileURL = ExtensionSharedConfig.configFileURL() else {
            return cacheFailure(fingerprint: nil, state: "getpwuid 取真实 home 失败，无法定位共享配置")
        }

        let fingerprint: Fingerprint
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            guard let modificationDate = attributes[.modificationDate] as? Date,
                  let fileSize = (attributes[.size] as? NSNumber)?.uint64Value else {
                return cacheFailure(fingerprint: nil, state: "共享配置文件属性缺少 mtime/size，无法建立缓存指纹")
            }
            fingerprint = Fingerprint(modificationDate: modificationDate, fileSize: fileSize)
        } catch CocoaError.fileReadNoSuchFile {
            return cacheFailure(fingerprint: nil, state: "共享配置不存在（主 App 可能尚未运行过）：\(fileURL.path)")
        } catch {
            // 最可能的失败点：temporary-exception entitlement 未生效（签名/路径不匹配）
            return cacheFailure(fingerprint: nil, state: "stat 共享配置失败（疑似沙盒拒绝）：\(error.localizedDescription)")
        }

        // 指纹未变：直接复用缓存。失败结果（如解码失败）也复用，
        // 避免对同一份损坏文件反复重读重解码
        if hasCache, fingerprint == cachedFingerprint {
            return cachedApps
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            return cacheFailure(fingerprint: fingerprint, state: "读取共享配置失败（疑似沙盒拒绝）：\(error.localizedDescription)")
        }

        let config: ExtensionSharedConfig
        do {
            config = try JSONDecoder().decode(ExtensionSharedConfig.self, from: data)
        } catch {
            return cacheFailure(fingerprint: fingerprint, state: "解码共享配置失败：\(error.localizedDescription)")
        }

        guard config.version == ExtensionSharedConfig.currentVersion else {
            // version 不识别说明两端 schema 不同步（如旧扩展读新配置），整份忽略最安全
            return cacheFailure(
                fingerprint: fingerprint,
                state: "共享配置 version 不识别：\(config.version)（当前支持 \(ExtensionSharedConfig.currentVersion)），已忽略"
            )
        }

        cachedFingerprint = fingerprint
        cachedApps = config.openWithApps
        hasCache = true
        logStateChangeOnce("共享配置已加载：openWithApps=\(config.openWithApps.count)")
        return config.openWithApps
    }

    /// 把失败态写入缓存并返回空列表。
    /// fingerprint 传入非 nil（stat 成功但读取/解码失败）时，文件不变就不会再重试；
    /// 传 nil（stat 之前就失败）时下次仍会重新尝试。
    private static func cacheFailure(fingerprint: Fingerprint?, state: String) -> [OpenWithApp] {
        cachedFingerprint = fingerprint
        cachedApps = []
        hasCache = true
        logStateChangeOnce(state)
        return []
    }

    /// 仅在状态（日志内容）变化时打日志：缓存命中路径完全静默，失败态只报一次。
    private static func logStateChangeOnce(_ message: String) {
        guard message != lastLoggedState else { return }
        lastLoggedState = message
        NSLog("[MenuPlus/FinderExt] %@", message)
    }
}
