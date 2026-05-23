//
//  FinderSync.swift
//  FinderExt
//
//  Finder Sync Extension 入口：注册全盘监控，提供 rightMenu 子菜单。
//

import Cocoa
import FinderSync

class FinderSync: FIFinderSync {

    override init() {
        super.init()

        NSLog("rightMenu FinderSync 已加载，bundle: %@", Bundle.main.bundlePath as NSString)

        // 监控全盘，使右键菜单在任意路径都可用
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    // MARK: - 基础观察方法（保留日志，便于真机调试）

    override func beginObservingDirectory(at url: URL) {
        // 用户开始查看某个目录时触发，无需特殊处理
    }

    override func endObservingDirectory(at url: URL) {
        // 用户离开目录时触发
    }

    override func requestBadgeIdentifier(for url: URL) {
        // 当前 MVP 不需要 badge
    }

    // MARK: - 工具栏项（保留兜底，未在主流程使用）

    override var toolbarItemName: String { "rightMenu" }
    override var toolbarItemToolTip: String { "rightMenu 右键菜单扩展" }
    override var toolbarItemImage: NSImage {
        NSImage(systemSymbolName: "filemenu.and.cursorarrow", accessibilityDescription: nil)
            ?? NSImage(named: NSImage.actionTemplateName)!
    }

    // MARK: - 主菜单构建

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        // 顶层菜单只放一个 "rightMenu" 项，子菜单挂载具体动作
        let topMenu = NSMenu(title: "")
        let parentItem = NSMenuItem(title: "rightMenu", action: nil, keyEquivalent: "")
        parentItem.submenu = buildSubmenu(menuKind: menuKind)
        topMenu.addItem(parentItem)
        return topMenu
    }

    /// 构建 rightMenu 子菜单。按选中目标的类型（文件 / 文件夹）过滤可用动作。
    private func buildSubmenu(menuKind: FIMenuKind) -> NSMenu {
        let submenu = NSMenu(title: "rightMenu")

        let targets = selectedTargets()

        // 用户是否明确右键选中了「全部都是文件夹」的若干项
        // （区别于右键空白区域：空白区域只有 targetedURL，没有 selectedItemURLs）
        let allSelectedAreFolders = !targets.isEmpty && targets.allSatisfy { $0.hasDirectoryPath }

        // 1. 在终端中打开（仅明确右键选中文件夹时显示）—— 走 IPC 由主 App 执行
        if menuKind == .contextualMenuForItems && allSelectedAreFolders {
            submenu.addItem(menuItem(title: "在终端中打开", selector: #selector(actionOpenInTerminal(_:))))
        }

        // 2. 在 VSCode 中打开（文件 + 文件夹皆可）—— 扩展内执行（vscode:// 走 LaunchServices 同源不受限）
        submenu.addItem(menuItem(title: "在 VSCode 中打开", selector: #selector(actionOpenInVSCode(_:))))

        // 3. 复制完整路径 —— 扩展内执行（Pasteboard 在扩展内可用）
        submenu.addItem(menuItem(title: "复制路径", selector: #selector(actionCopyFullPath(_:))))

        // 4. 复制文件(夹)名 —— 扩展内执行
        submenu.addItem(menuItem(title: "复制文件(夹)名", selector: #selector(actionCopyFileName(_:))))

        // 5. 新建空白文件 —— 仅明确右键选中文件夹时显示 —— 走 IPC
        if menuKind == .contextualMenuForItems && allSelectedAreFolders {
            submenu.addItem(menuItem(title: "新建空白文件", selector: #selector(actionCreateBlankFile(_:))))
        }

        // 6. 新建 txt 文件 —— 仅明确右键选中文件夹时显示 —— 走 IPC
        if menuKind == .contextualMenuForItems && allSelectedAreFolders {
            submenu.addItem(menuItem(title: "新建 txt 文件", selector: #selector(actionCreateTxtFile(_:))))
        }

        // 8. 在新窗口打开（必须右键文件夹图标，右键空白区域不显示）—— 走 IPC
        // menuKind == .contextualMenuForItems 确保是右键选中项而非空白区域
        if menuKind == .contextualMenuForItems && allSelectedAreFolders {
            submenu.addItem(menuItem(title: "在新窗口打开", selector: #selector(actionOpenInNewFinderWindow(_:))))
        }

        return submenu
    }

    /// 统一构造一个 target=self 的 NSMenuItem。
    private func menuItem(title: String, selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    /// 获取当前右键选中的目标 URL 列表。
    /// 优先使用 selectedItemURLs；若为空（例如右键空白区域），回退到 targetedURL。
    private func selectedTargets() -> [URL] {
        if let selected = FIFinderSyncController.default().selectedItemURLs(), !selected.isEmpty {
            return selected
        }
        if let target = FIFinderSyncController.default().targetedURL() {
            return [target]
        }
        return []
    }

    // MARK: - 动作分发
    //
    // 走 IPC 的动作（受 sandbox 限制）：1/5/6/8
    // 扩展内直接执行的动作（sandbox 允许）：2/3/4

    @objc private func actionOpenInTerminal(_ sender: AnyObject?) {
        for url in selectedTargets() where url.hasDirectoryPath {
            IPCClient.send(IPCRequest(action: .openInTerminal, paths: [url.path]))
        }
    }

    @objc private func actionOpenInVSCode(_ sender: AnyObject?) {
        for url in selectedTargets() {
            FinderSyncActions.openInVSCode(url: url)
        }
    }

    @objc private func actionCopyFullPath(_ sender: AnyObject?) {
        let paths = selectedTargets().map { $0.path }
        guard !paths.isEmpty else { return }
        FinderSyncActions.copyToClipboard(paths.joined(separator: "\n"))
    }

    @objc private func actionCopyFileName(_ sender: AnyObject?) {
        let names = selectedTargets().map { $0.lastPathComponent }
        guard !names.isEmpty else { return }
        FinderSyncActions.copyToClipboard(names.joined(separator: "\n"))
    }

    @objc private func actionCreateBlankFile(_ sender: AnyObject?) {
        for url in selectedTargets() where url.hasDirectoryPath {
            IPCClient.send(IPCRequest(action: .createBlankFile, paths: [url.path]))
        }
    }

    @objc private func actionCreateTxtFile(_ sender: AnyObject?) {
        for url in selectedTargets() where url.hasDirectoryPath {
            IPCClient.send(IPCRequest(action: .createTxtFile, paths: [url.path]))
        }
    }

    @objc private func actionOpenInNewFinderWindow(_ sender: AnyObject?) {
        for url in selectedTargets() where url.hasDirectoryPath {
            IPCClient.send(IPCRequest(action: .openInNewFinderWindow, paths: [url.path]))
        }
    }
}
