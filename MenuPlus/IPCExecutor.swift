//
//  IPCExecutor.swift
//  MenuPlus
//
//  主 App 端 IPC 动作执行器。
//  Finder 扩展把受限动作交给这里执行；这里负责权限提示、失败反馈和异步执行。
//

import AppKit

enum IPCExecutor {
    private static let queue = DispatchQueue(label: "MenuPlus.IPCExecutor", qos: .userInitiated)

    static func execute(_ request: IPCRequest) {
        queue.async {
            perform(request)
        }
    }

    private static func perform(_ request: IPCRequest) {
        switch request.action {
        case .openInTerminal:
            openInTerminal(paths: request.paths)

        case .openInNewFinderWindow:
            openInNewFinderWindows(paths: request.paths)
        }
    }

    // MARK: - 具体动作

    private static func openInTerminal(paths: [String]) {
        let urls = paths.map(URL.init(fileURLWithPath:))
        guard !urls.isEmpty else {
            return FailurePresenter.present(action: "在终端打开", reason: "缺少目标路径")
        }

        let terminalURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false

        NSWorkspace.shared.open(
            urls,
            withApplicationAt: terminalURL,
            configuration: config
        ) { _, error in
            if let error {
                FailurePresenter.present(action: "在终端打开", reason: error.localizedDescription)
            }
        }
    }

    private static func openInNewFinderWindows(paths: [String]) {
        guard !paths.isEmpty else {
            return FailurePresenter.present(action: "在新窗口打开", reason: "缺少目标路径")
        }

        for path in paths {
            openFinderWindow(path: path)
        }
    }

    private static func openFinderWindow(path: String) {
        let escapedPath = path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")

        let source = "tell application \"Finder\" to make new Finder window to (POSIX file \"\(escapedPath)\")"
        guard let script = NSAppleScript(source: source) else {
            return FailurePresenter.present(action: "在新窗口打开", reason: "脚本初始化失败")
        }

        var error: NSDictionary?
        script.executeAndReturnError(&error)
        guard let error else { return }

        let errorNumber = error[NSAppleScript.errorNumber] as? Int ?? 0
        let message = (error[NSAppleScript.errorMessage] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = message?.isEmpty == false ? message! : "无法打开 \(path)"

        if errorNumber == -1743 {
            FailurePresenter.present(
                action: "在新窗口打开",
                reason: reason,
                guidance: .automation(targetApp: "Finder")
            )
            return
        }

        FailurePresenter.present(action: "在新窗口打开", reason: reason)
    }
}
