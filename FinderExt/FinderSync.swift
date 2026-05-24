//
//  FinderSync.swift
//  FinderExt
//
//  Finder Sync Extension 入口：注册全盘监控，直接在 Finder 右键菜单里输出可用动作。
//

import Cocoa
import FinderSync

class FinderSync: FIFinderSync {
    private let controller = FIFinderSyncController.default()

    override init() {
        super.init()

        NSLog("MenuPlus FinderSync 已加载，bundle: %@", Bundle.main.bundlePath as NSString)

        // 监控全盘，使右键菜单在任意路径都可用。
        controller.directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override func beginObservingDirectory(at url: URL) {}
    override func endObservingDirectory(at url: URL) {}
    override func requestBadgeIdentifier(for url: URL) {}

    override var toolbarItemName: String { "MenuPlus" }
    override var toolbarItemToolTip: String { "MenuPlus 右键菜单扩展" }
    override var toolbarItemImage: NSImage {
        NSImage(systemSymbolName: "filemenu.and.cursorarrow", accessibilityDescription: nil)
            ?? NSImage(named: NSImage.actionTemplateName)!
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let menu = NSMenu(title: "")

        let terminalTargets = terminalTargets(for: menuKind)
        if !terminalTargets.isEmpty {
            menu.addItem(menuItem(title: "在终端中打开", selector: #selector(actionOpenInTerminal(_:))))
        }

        let vscodeTargets = generalTargets(for: menuKind)
        if !vscodeTargets.isEmpty {
            menu.addItem(menuItem(title: "在 VSCode 中打开", selector: #selector(actionOpenInVSCode(_:))))
            menu.addItem(menuItem(title: "复制路径", selector: #selector(actionCopyFullPath(_:))))
            menu.addItem(menuItem(title: "复制文件(夹)名", selector: #selector(actionCopyFileName(_:))))
        }

        let creatableFolders = creatableFolderTargets()
        if !creatableFolders.isEmpty {
            addSeparatorIfNeeded(to: menu)
            menu.addItem(menuItem(title: "新建空白文件", selector: #selector(actionCreateBlankFile(_:))))
            menu.addItem(menuItem(title: "新建 txt 文件", selector: #selector(actionCreateTxtFile(_:))))
        }

        let newWindowFolders = newWindowTargets(for: menuKind)
        if !newWindowFolders.isEmpty {
            addSeparatorIfNeeded(to: menu)
            menu.addItem(menuItem(title: "在新窗口打开", selector: #selector(actionOpenInNewFinderWindow(_:))))
        }

        return menu.items.isEmpty ? nil : menu
    }

    private func menuItem(title: String, selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    private func addSeparatorIfNeeded(to menu: NSMenu) {
        guard !menu.items.isEmpty, menu.items.last?.isSeparatorItem == false else { return }
        menu.addItem(.separator())
    }

    private func selectedItems() -> [URL] {
        controller.selectedItemURLs() ?? []
    }

    private func targetedURL() -> URL? {
        controller.targetedURL()
    }

    private func isActionableFolder(_ url: URL) -> Bool {
        url.hasDirectoryPath && !NSWorkspace.shared.isFilePackage(atPath: url.path)
    }

    private func selectedFolders() -> [URL] {
        selectedItems().filter(isActionableFolder)
    }

    private func allSelectedItemsAreFolders() -> Bool {
        let selected = selectedItems()
        return !selected.isEmpty && selected.allSatisfy(isActionableFolder)
    }

    private func generalTargets(for menuKind: FIMenuKind) -> [URL] {
        let selected = selectedItems()
        if !selected.isEmpty {
            return selected
        }

        guard menuKind == .contextualMenuForContainer || menuKind == .contextualMenuForSidebar,
              let target = targetedURL() else {
            return []
        }
        return [target]
    }

    private func terminalTargets(for menuKind: FIMenuKind) -> [URL] {
        if allSelectedItemsAreFolders() {
            return selectedFolders()
        }

        guard menuKind == .contextualMenuForContainer || menuKind == .contextualMenuForSidebar,
              let target = targetedURL(),
              isActionableFolder(target) else {
            return []
        }
        return [target]
    }

    /// 仅允许“明确选中的文件夹”显示新建文件，避免右键空白区域时拿不到写权限。
    private func creatableFolderTargets() -> [URL] {
        guard allSelectedItemsAreFolders() else { return [] }
        return selectedFolders()
    }

    private func newWindowTargets(for menuKind: FIMenuKind) -> [URL] {
        guard menuKind == .contextualMenuForItems, allSelectedItemsAreFolders() else { return [] }
        return selectedFolders()
    }

    @objc private func actionOpenInTerminal(_ sender: AnyObject?) {
        let paths = terminalTargets(for: .contextualMenuForContainer).map(\.path)
        guard !paths.isEmpty else { return }
        IPCClient.send(IPCRequest(action: .openInTerminal, paths: paths))
    }

    @objc private func actionOpenInVSCode(_ sender: AnyObject?) {
        for url in generalTargets(for: .contextualMenuForContainer) {
            FinderSyncActions.openInVSCode(url: url)
        }
    }

    @objc private func actionCopyFullPath(_ sender: AnyObject?) {
        let paths = generalTargets(for: .contextualMenuForContainer).map(\.path)
        guard !paths.isEmpty else { return }
        FinderSyncActions.copyToClipboard(paths.joined(separator: "\n"))
    }

    @objc private func actionCopyFileName(_ sender: AnyObject?) {
        let names = generalTargets(for: .contextualMenuForContainer).map(\.lastPathComponent)
        guard !names.isEmpty else { return }
        FinderSyncActions.copyToClipboard(names.joined(separator: "\n"))
    }

    @objc private func actionCreateBlankFile(_ sender: AnyObject?) {
        for url in creatableFolderTargets() {
            FinderSyncActions.createFile(inDirectory: url.path, baseName: "新建文件", extension: nil)
        }
    }

    @objc private func actionCreateTxtFile(_ sender: AnyObject?) {
        for url in creatableFolderTargets() {
            FinderSyncActions.createFile(inDirectory: url.path, baseName: "新建文件", extension: "txt")
        }
    }

    @objc private func actionOpenInNewFinderWindow(_ sender: AnyObject?) {
        let paths = newWindowTargets(for: .contextualMenuForItems).map(\.path)
        guard !paths.isEmpty else { return }
        IPCClient.send(IPCRequest(action: .openInNewFinderWindow, paths: paths))
    }
}
