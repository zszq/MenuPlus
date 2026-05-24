//
//  IPCAction.swift
//  MenuPlus
//
//  ⚠️ 这个文件必须和 FinderExt/IPCAction.swift 保持完全一致
//  （Xcode FileSystemSynchronizedRootGroup 不跨目录共享文件，
//   故在两个 target 各放一份完全相同的源码；任何修改请同步两份。）
//
//  扩展与 MenuPlus 主 App 之间的 IPC 协议：
//      扩展端构造 IPCRequest → URL("rightmenu://<action>?paths=<base64-json>")
//      主 App 端 application(_:open:) 收到后 IPCRequest.from(url:) 反向解析
//

import Foundation

enum IPCAction: String, Codable {
    case openInTerminal
    case openInNewFinderWindow
    // 未来可扩展更多动作
}

struct IPCRequest {
    let action: IPCAction
    /// 目标文件 / 文件夹的绝对路径列表
    let paths: [String]

    /// 编码成 URL: rightmenu://<action>?paths=<base64-json>
    /// 用 JSON + base64 编码，避免 query string 中特殊字符（空格、中文、#、& 等）的转义问题
    func toURL() -> URL? {
        var comp = URLComponents()
        comp.scheme = "rightmenu"
        comp.host = action.rawValue
        guard let json = try? JSONEncoder().encode(paths),
              let b64 = String(data: json.base64EncodedData(), encoding: .utf8) else {
            return nil
        }
        comp.queryItems = [URLQueryItem(name: "paths", value: b64)]
        return comp.url
    }

    /// 从主 App 收到的 URL 反向解析
    static func from(url: URL) -> IPCRequest? {
        guard url.scheme == "rightmenu",
              let host = url.host,
              let action = IPCAction(rawValue: host) else { return nil }
        let comp = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let b64 = comp?.queryItems?.first(where: { $0.name == "paths" })?.value,
              let data = Data(base64Encoded: b64),
              let paths = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }
        return IPCRequest(action: action, paths: paths)
    }
}
