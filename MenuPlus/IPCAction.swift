//
//  IPCAction.swift
//  MenuPlus
//
//  ⚠️ 这个文件必须和 FinderExt/IPCAction.swift 保持完全一致
//  （Xcode FileSystemSynchronizedRootGroup 不跨目录共享文件，
//   故在两个 target 各放一份完全相同的源码；任何修改请同步两份。）
//
//  扩展与主 App 之间的 IPC 协议：
//      扩展端构造 IPCRequest → URL("menuplus://<action>?paths=<base64-json>")
//      主 App 端 application(_:open:) 收到后 IPCRequest.from(url:) 反向解析
//

import Foundation

enum IPCAction: String, Codable {
    case openInTerminal
    case createBlankFile
    case createTxtFile
    case openInNewFinderWindow
    case createFromTemplate
    case openWithApp
    // 未来可扩展更多动作

    static func resolve(from rawValue: String) -> IPCAction? {
        allCases.first { $0.rawValue.caseInsensitiveCompare(rawValue) == .orderedSame }
    }
}

extension IPCAction: CaseIterable {}

/// "MenuPlus新建" 菜单的内置模板清单。
/// 与 IPCAction 同受双端同步约定保护：扩展端用它生成菜单项，
/// 主 App 端用 rawValue（即 IPCRequest.templateID）反查模板并提供文件内容。
/// ⚠️ case 声明顺序即 allCases 顺序，直接决定"MenuPlus新建"菜单排序
/// （Office 三件套在前，Markdown / RTF 殿后）；菜单 tag=下标由扩展同进程
/// 构建并消费，重排安全；rawValue 不变，IPC 协议不受影响。
enum FileTemplate: String, Codable, CaseIterable {
    case word
    case excel
    case powerpoint
    case markdown
    case rtf

    /// 右键菜单中显示的标题
    var menuTitle: String {
        switch self {
        case .word: return "Word 文档"
        case .excel: return "Excel 工作簿"
        case .powerpoint: return "PowerPoint 演示文稿"
        case .markdown: return "Markdown 文档"
        case .rtf: return "RTF 文档"
        }
    }

    /// 创建文件的默认名（不含扩展名；重名时由主 App 创建逻辑递增 " 2/3…"）
    var baseName: String {
        switch self {
        case .word: return "新建 Word 文档"
        case .excel: return "新建 Excel 工作簿"
        case .powerpoint: return "新建 PowerPoint 演示文稿"
        case .markdown: return "新建 Markdown 文档"
        case .rtf: return "新建 RTF 文档"
        }
    }

    /// 文件扩展名（不含点）
    var fileExtension: String {
        switch self {
        case .word: return "docx"
        case .excel: return "xlsx"
        case .powerpoint: return "pptx"
        case .markdown: return "md"
        case .rtf: return "rtf"
        }
    }
}

/// 主 App 写、Finder 扩展读的跨进程共享配置契约。
/// ad-hoc 签名下 application-groups entitlement 构建期被拒（无 App Group）；
/// 主 App 沙盒容器受系统保护，扩展读取实测被拒。故改为：
/// 共享文件放真实 home 下的中立路径（不在任何容器内、不在 TCC 保护路径内），
/// 双端用 temporary-exception.files.home-relative-path entitlement 打通
/// （主 App 读写、扩展只读，详见各自 .entitlements 内注释）。
/// ⚠️ schema 变更必须升 version；扩展端遇到不识别的 version 一律忽略整份配置（优雅降级）。
struct ExtensionSharedConfig: Codable {
    /// 当前 schema 版本
    static let currentVersion = 1

    /// 配置文件的子目录名与文件名（两端共用，避免拼写漂移；
    /// 必须与双端 entitlements 中 temporary-exception 声明的路径一致）
    static let configDirectoryName = "MenuPlus"
    static let configFileName = "extension-config.json"

    /// 相对**真实 home**（非沙盒容器）的完整相对路径，
    /// 与 entitlements 里 home-relative-path exception 的语义一致。
    static let relativePath = "Library/Application Support/\(configDirectoryName)/\(configFileName)"

    /// 共享配置文件的绝对路径；nil 表示无法解析真实 home（调用方负责 NSLog 后降级）。
    /// 双端共用同一段代码，路径逻辑天然一致。
    /// 沙盒内 NSHomeDirectory() / FileManager.urls(for: .applicationSupportDirectory)
    /// 都指向各自的容器，必须通过 getpwuid 读 passwd 记录拿真实 home。
    static func configFileURL() -> URL? {
        guard let passwd = getpwuid(getuid()), let homeCString = passwd.pointee.pw_dir else {
            return nil
        }
        // getpwuid 返回静态缓冲区，立即拷贝成 String；pw_dir 为空串时
        // URL(fileURLWithPath:) 会解析成相对当前目录的路径，必须视为解析失败
        let realHome = String(cString: homeCString)
        guard !realHome.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: realHome, isDirectory: true)
            .appendingPathComponent(relativePath, isDirectory: false)
    }

    let version: Int
    let openWithApps: [OpenWithApp]
}

/// "用 XX 打开" 的单个应用配置
struct OpenWithApp: Codable, Equatable {
    /// 右键菜单显示名
    let name: String
    /// .app 的绝对路径
    let path: String
}

struct IPCRequest {
    let action: IPCAction
    /// 目标文件 / 文件夹的绝对路径列表
    let paths: [String]
    /// createFromTemplate 专用：FileTemplate.rawValue；其余动作为 nil
    let templateID: String?
    /// openWithApp 专用：目标 .app 的绝对路径；其余动作为 nil
    let appPath: String?

    /// templateID / appPath 默认 nil，保证旧动作的调用点与 URL 格式完全不变（向后兼容）
    init(action: IPCAction, paths: [String], templateID: String? = nil, appPath: String? = nil) {
        self.action = action
        self.paths = paths
        self.templateID = templateID
        self.appPath = appPath
    }

    /// 编码成 URL: menuplus://<action>?paths=<base64-json>[&template=<id>][&appPath=<path>]
    /// paths 用 JSON + base64 编码，避免 query string 中特殊字符（空格、中文、#、& 等）的转义问题
    func toURL() -> URL? {
        var comp = URLComponents()
        comp.scheme = "menuplus"
        comp.host = "ipc"
        guard let json = try? JSONEncoder().encode(paths),
              let b64 = String(data: json.base64EncodedData(), encoding: .utf8) else {
            return nil
        }
        var queryItems = [
            URLQueryItem(name: "action", value: action.rawValue),
            URLQueryItem(name: "paths", value: b64)
        ]
        if let templateID {
            queryItems.append(URLQueryItem(name: "template", value: templateID))
        }
        if let appPath {
            // 单个路径走 URLQueryItem 自动百分号转义即可，无需像 paths 一样 base64
            queryItems.append(URLQueryItem(name: "appPath", value: appPath))
        }
        comp.queryItems = queryItems
        return comp.url
    }

    /// 从主 App 收到的 URL 反向解析
    static func from(url: URL) -> IPCRequest? {
        let comp = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard url.scheme == "menuplus" else { return nil }

        let actionRawValue =
            comp?.queryItems?.first(where: { $0.name == "action" })?.value
            ?? url.host
            ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard let action = IPCAction.resolve(from: actionRawValue) else {
            return nil
        }

        guard let b64 = comp?.queryItems?.first(where: { $0.name == "paths" })?.value,
              let data = Data(base64Encoded: b64),
              let paths = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }

        let templateID = comp?.queryItems?.first(where: { $0.name == "template" })?.value
        let appPath = comp?.queryItems?.first(where: { $0.name == "appPath" })?.value
        return IPCRequest(action: action, paths: paths, templateID: templateID, appPath: appPath)
    }
}
