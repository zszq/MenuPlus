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

        case .createBlankFile:
            createFiles(paths: request.paths, baseName: "新建文件", fileExtension: nil, actionName: "新建文件")

        case .createTxtFile:
            createFiles(paths: request.paths, baseName: "新建文件", fileExtension: "txt", actionName: "新建 txt 文件")

        case .openInNewFinderWindow:
            openInNewFinderWindows(paths: request.paths)
        }
    }

    // MARK: - 具体动作

    private static func openInTerminal(paths: [String]) {
        guard !paths.isEmpty else {
            return FailurePresenter.present(action: "在终端打开", reason: "缺少目标路径")
        }

        for path in paths {
            do {
                try SecurityScopedDirectoryStore.withAccess(to: path, actionName: "在终端打开") { directoryURL in
                    try openTerminal(directoryURL: directoryURL)
                }
            } catch {
                FailurePresenter.present(action: "在终端打开", reason: error.localizedDescription)
            }
        }
    }

    private static func openTerminal(directoryURL: URL) throws {
        let terminalURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        guard FileManager.default.fileExists(atPath: terminalURL.path) else {
            throw NSError(
                domain: "MenuPlus.IPCExecutor",
                code: 10,
                userInfo: [NSLocalizedDescriptionKey: "未找到 Terminal.app"]
            )
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        let semaphore = DispatchSemaphore(value: 0)
        var completionError: Error?

        NSWorkspace.shared.open(
            [directoryURL],
            withApplicationAt: terminalURL,
            configuration: configuration
        ) { _, error in
            completionError = error
            semaphore.signal()
        }

        semaphore.wait()

        if let completionError {
            throw completionError
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

    private static func createFiles(
        paths: [String],
        baseName: String,
        fileExtension: String?,
        actionName: String
    ) {
        guard !paths.isEmpty else {
            return FailurePresenter.present(action: actionName, reason: "缺少目标路径")
        }

        for path in paths {
            do {
                try SecurityScopedDirectoryStore.withAccess(to: path, actionName: actionName) { directoryURL in
                    try createFile(in: directoryURL, baseName: baseName, fileExtension: fileExtension)
                }
            } catch {
                FailurePresenter.present(action: actionName, reason: error.localizedDescription)
            }
        }
    }

    private static func createFile(
        in directoryURL: URL,
        baseName: String,
        fileExtension: String?
    ) throws {
        let suffix = fileExtension.map { ".\($0)" } ?? ""
        var candidateName = "\(baseName)\(suffix)"
        var index = 2

        while FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent(candidateName).path) {
            candidateName = "\(baseName) \(index)\(suffix)"
            index += 1
        }

        let targetURL = directoryURL.appendingPathComponent(candidateName)
        let created = FileManager.default.createFile(atPath: targetURL.path, contents: nil)
        guard created else {
            throw NSError(
                domain: "MenuPlus.IPCExecutor",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "无法在 \(directoryURL.path) 创建 \(candidateName)"]
            )
        }
    }
}
