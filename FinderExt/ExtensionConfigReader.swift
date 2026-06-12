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

import Foundation

enum ExtensionConfigReader {

    /// 读取自定义"用 XX 打开"应用列表；任何失败返回 []（调用方据此隐藏自定义菜单项）。
    static func load() -> [OpenWithApp] {
        // 路径解析统一走契约里的 configFileURL()（getpwuid 取真实 home），与主 App 写出逻辑一致
        guard let fileURL = ExtensionSharedConfig.configFileURL() else {
            NSLog("[MenuPlus/FinderExt] getpwuid 取真实 home 失败，无法定位共享配置")
            return []
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            NSLog("[MenuPlus/FinderExt] 共享配置不存在（主 App 可能尚未运行过）：%@", fileURL.path)
            return []
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            // 最可能的失败点：temporary-exception entitlement 未生效（签名/路径不匹配）
            NSLog("[MenuPlus/FinderExt] 读取共享配置失败（疑似沙盒拒绝）：%@", error.localizedDescription)
            return []
        }

        let config: ExtensionSharedConfig
        do {
            config = try JSONDecoder().decode(ExtensionSharedConfig.self, from: data)
        } catch {
            NSLog("[MenuPlus/FinderExt] 解码共享配置失败：%@", error.localizedDescription)
            return []
        }

        guard config.version == ExtensionSharedConfig.currentVersion else {
            // version 不识别说明两端 schema 不同步（如旧扩展读新配置），整份忽略最安全
            NSLog(
                "[MenuPlus/FinderExt] 共享配置 version 不识别：%d（当前支持 %d），已忽略",
                config.version,
                ExtensionSharedConfig.currentVersion
            )
            return []
        }

        return config.openWithApps
    }
}
