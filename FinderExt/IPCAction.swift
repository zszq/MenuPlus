//
//  IPCAction.swift
//  FinderExt
//
//  ⚠️ 这个文件必须和 MenuPlus/IPCAction.swift 保持完全一致
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
    // 未来可扩展更多动作

    static func resolve(from rawValue: String) -> IPCAction? {
        allCases.first { $0.rawValue.caseInsensitiveCompare(rawValue) == .orderedSame }
    }
}

extension IPCAction: CaseIterable {}

/// "MenuPlus新建" 菜单的内置模板清单。
/// 与 IPCAction 同受双端同步约定保护：扩展端用它生成菜单项，
/// 主 App 端用 rawValue（即 IPCRequest.templateID）反查模板并提供文件内容。
enum FileTemplate: String, Codable, CaseIterable {
    case markdown
    case rtf
    case word
    case excel
    case powerpoint

    /// 右键菜单中显示的标题
    var menuTitle: String {
        switch self {
        case .markdown: return "Markdown 文档"
        case .rtf: return "RTF 文档"
        case .word: return "Word 文档"
        case .excel: return "Excel 工作簿"
        case .powerpoint: return "PowerPoint 演示文稿"
        }
    }

    /// 创建文件的默认名（不含扩展名；重名时由主 App 创建逻辑递增 " 2/3…"）
    var baseName: String {
        switch self {
        case .markdown: return "新建 Markdown 文档"
        case .rtf: return "新建 RTF 文档"
        case .word: return "新建 Word 文档"
        case .excel: return "新建 Excel 工作簿"
        case .powerpoint: return "新建 PowerPoint 演示文稿"
        }
    }

    /// 文件扩展名（不含点）
    var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .rtf: return "rtf"
        case .word: return "docx"
        case .excel: return "xlsx"
        case .powerpoint: return "pptx"
        }
    }
}

struct IPCRequest {
    let action: IPCAction
    /// 目标文件 / 文件夹的绝对路径列表
    let paths: [String]
    /// createFromTemplate 专用：FileTemplate.rawValue；其余动作为 nil
    let templateID: String?

    /// templateID 默认 nil，保证旧动作的调用点与 URL 格式完全不变（向后兼容）
    init(action: IPCAction, paths: [String], templateID: String? = nil) {
        self.action = action
        self.paths = paths
        self.templateID = templateID
    }

    /// 编码成 URL: menuplus://<action>?paths=<base64-json>[&template=<id>]
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
        return IPCRequest(action: action, paths: paths, templateID: templateID)
    }
}
