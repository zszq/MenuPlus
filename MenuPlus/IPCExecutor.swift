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
            createFiles(paths: request.paths, baseName: "新建文件", fileExtension: nil, contents: nil, actionName: "新建文件")

        case .createTxtFile:
            createFiles(paths: request.paths, baseName: "新建文件", fileExtension: "txt", contents: nil, actionName: "新建 txt 文件")

        case .openInNewFinderWindow:
            openInNewFinderWindows(paths: request.paths)

        case .createFromTemplate:
            createFromTemplate(request)
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
            do {
                try SecurityScopedDirectoryStore.withAccess(to: path, actionName: "在新窗口打开") { directoryURL in
                    try openFinderWindow(directoryURL: directoryURL)
                }
            } catch {
                FailurePresenter.present(action: "在新窗口打开", reason: error.localizedDescription)
            }
        }
    }

    private static func openFinderWindow(directoryURL: URL) throws {
        let finderAppURL =
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder")
            ?? URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")

        guard FileManager.default.fileExists(atPath: finderAppURL.path) else {
            throw NSError(
                domain: "MenuPlus.IPCExecutor",
                code: 11,
                userInfo: [NSLocalizedDescriptionKey: "未找到 Finder.app"]
            )
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        let semaphore = DispatchSemaphore(value: 0)
        var completionError: Error?

        NSWorkspace.shared.open(
            [directoryURL],
            withApplicationAt: finderAppURL,
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

    /// 按内置模板创建文件：解析 templateID → 取模板内容 → 走通用创建链路。
    /// 模板内容在授权前一次性取出，资源缺失时不弹授权面板直接报错。
    private static func createFromTemplate(_ request: IPCRequest) {
        guard let templateID = request.templateID,
              let template = FileTemplate(rawValue: templateID) else {
            return FailurePresenter.present(
                action: "新建文件",
                reason: "无法识别的模板类型：\(request.templateID ?? "（缺失）")"
            )
        }

        let actionName = "新建 \(template.menuTitle)"
        do {
            let contents = try TemplateProvider.content(for: template)
            createFiles(
                paths: request.paths,
                baseName: template.baseName,
                fileExtension: template.fileExtension,
                contents: contents,
                actionName: actionName
            )
        } catch {
            FailurePresenter.present(action: actionName, reason: error.localizedDescription)
        }
    }

    private static func createFiles(
        paths: [String],
        baseName: String,
        fileExtension: String?,
        contents: Data?,
        actionName: String
    ) {
        guard !paths.isEmpty else {
            return FailurePresenter.present(action: actionName, reason: "缺少目标路径")
        }

        for path in paths {
            do {
                try SecurityScopedDirectoryStore.withAccess(to: path, actionName: actionName) { directoryURL in
                    try createFile(in: directoryURL, baseName: baseName, fileExtension: fileExtension, contents: contents)
                }
            } catch {
                FailurePresenter.present(action: actionName, reason: error.localizedDescription)
            }
        }
    }

    private static func createFile(
        in directoryURL: URL,
        baseName: String,
        fileExtension: String?,
        contents: Data?
    ) throws {
        let suffix = fileExtension.map { ".\($0)" } ?? ""
        var candidateName = "\(baseName)\(suffix)"
        var index = 2

        while FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent(candidateName).path) {
            candidateName = "\(baseName) \(index)\(suffix)"
            index += 1
        }

        let targetURL = directoryURL.appendingPathComponent(candidateName)
        let created = FileManager.default.createFile(atPath: targetURL.path, contents: contents)
        guard created else {
            throw NSError(
                domain: "MenuPlus.IPCExecutor",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "无法在 \(directoryURL.path) 创建 \(candidateName)"]
            )
        }
    }
}
