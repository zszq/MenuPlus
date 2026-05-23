//
//  FinderSync.swift
//  FinderExt
//
//  Finder Sync Extension 主类，负责注册监控目录和提供右键菜单。
//

import Cocoa
import FinderSync

class FinderSync: FIFinderSync {

    override init() {
        super.init()
        // 监控根目录（全盘）
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    // MARK: - 菜单构建

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "")

        // 获取当前选中项
        let items = FIFinderSyncController.default().selectedItemURLs() ?? []
        // 判断选中项是否包含文件夹（用于决定显示哪些菜单项）
        let hasFolder = items.contains { url in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            return isDir.boolValue
        }
        let hasFile = items.contains { url in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            return !isDir.boolValue
        }

        // 动作 1：在终端中打开（仅文件夹）
        if hasFolder {
            let terminalItem = NSMenuItem(
                title: "在终端中打开",
                action: #selector(openInTerminal),
                keyEquivalent: ""
            )
            terminalItem.target = self
            menu.addItem(terminalItem)
        }

        // 动作 2：在 VSCode 中打开（文件夹 + 文件）
        if hasFolder || hasFile {
            let vscodeItem = NSMenuItem(
                title: "在 VSCode 中打开",
                action: #selector(openInVSCode),
                keyEquivalent: ""
            )
            vscodeItem.target = self
            menu.addItem(vscodeItem)
        }

        // 动作 3：复制完整路径（文件夹 + 文件）
        if hasFolder || hasFile {
            let copyPathItem = NSMenuItem(
                title: "复制完整路径",
                action: #selector(copyFullPath),
                keyEquivalent: ""
            )
            copyPathItem.target = self
            menu.addItem(copyPathItem)
        }

        // 动作 4：复制文件名（文件夹 + 文件）
        if hasFolder || hasFile {
            let copyNameItem = NSMenuItem(
                title: "复制文件名",
                action: #selector(copyFileName),
                keyEquivalent: ""
            )
            copyNameItem.target = self
            menu.addItem(copyNameItem)
        }

        // 动作 5：新建空白文件（仅文件夹）
        if hasFolder {
            let newFileItem = NSMenuItem(
                title: "新建空白文件",
                action: #selector(createBlankFile),
                keyEquivalent: ""
            )
            newFileItem.target = self
            menu.addItem(newFileItem)
        }

        // 动作 6：新建 txt 文件（仅文件夹）
        if hasFolder {
            let newTxtItem = NSMenuItem(
                title: "新建 txt 文件",
                action: #selector(createTxtFile),
                keyEquivalent: ""
            )
            newTxtItem.target = self
            menu.addItem(newTxtItem)
        }

        // 动作 7：显示/隐藏隐藏文件（文件夹 + 文件）
        if hasFolder || hasFile {
            let currentlyShowing = FinderSyncActions.hiddenFilesVisible()
            let toggleTitle = currentlyShowing ? "隐藏隐藏文件" : "显示隐藏文件"
            let toggleItem = NSMenuItem(
                title: toggleTitle,
                action: #selector(toggleHiddenFiles),
                keyEquivalent: ""
            )
            toggleItem.target = self
            menu.addItem(toggleItem)
        }

        // 动作 8：在新 Finder 窗口中打开（仅文件夹）
        if hasFolder {
            let newWindowItem = NSMenuItem(
                title: "在新 Finder 窗口中打开",
                action: #selector(openInNewFinderWindow),
                keyEquivalent: ""
            )
            newWindowItem.target = self
            menu.addItem(newWindowItem)
        }

        return menu
    }

    // MARK: - 动作处理

    @objc func openInTerminal() {
        guard let items = FIFinderSyncController.default().selectedItemURLs() else { return }
        for url in items {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                FinderSyncActions.openInTerminal(url: url)
            }
        }
    }

    @objc func openInVSCode() {
        guard let items = FIFinderSyncController.default().selectedItemURLs() else { return }
        for url in items {
            FinderSyncActions.openInVSCode(url: url)
        }
    }

    @objc func copyFullPath() {
        guard let items = FIFinderSyncController.default().selectedItemURLs() else { return }
        let paths = items.map { $0.path }.joined(separator: "\n")
        FinderSyncActions.copyToClipboard(paths)
    }

    @objc func copyFileName() {
        guard let items = FIFinderSyncController.default().selectedItemURLs() else { return }
        let names = items.map { $0.lastPathComponent }.joined(separator: "\n")
        FinderSyncActions.copyToClipboard(names)
    }

    @objc func createBlankFile() {
        guard let items = FIFinderSyncController.default().selectedItemURLs() else { return }
        for url in items {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                FinderSyncActions.createBlankFile(inDirectory: url, extension: nil)
            }
        }
    }

    @objc func createTxtFile() {
        guard let items = FIFinderSyncController.default().selectedItemURLs() else { return }
        for url in items {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                FinderSyncActions.createBlankFile(inDirectory: url, extension: "txt")
            }
        }
    }

    @objc func toggleHiddenFiles() {
        FinderSyncActions.toggleHiddenFiles()
    }

    @objc func openInNewFinderWindow() {
        guard let items = FIFinderSyncController.default().selectedItemURLs() else { return }
        for url in items {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
