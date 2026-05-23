//
//  IPCClient.swift
//  FinderExt
//
//  扩展端的 IPC 客户端：把 IPCRequest 编码成 rightmenu:// URL 后
//  交给 LaunchServices 唤起主 App 执行（绕开 FinderSync 的 sandbox 限制）。
//

import AppKit

enum IPCClient {
    static func send(_ request: IPCRequest) {
        guard let url = request.toURL() else {
            NSLog("[rightMenu/FinderExt] IPC 请求构造失败: action=%@", request.action.rawValue)
            return
        }
        NSWorkspace.shared.open(url)
        NSLog(
            "[rightMenu/FinderExt] 已发送 IPC: %@, paths=%d",
            request.action.rawValue,
            request.paths.count
        )
    }
}
