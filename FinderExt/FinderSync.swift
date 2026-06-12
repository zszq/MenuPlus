//
//  FinderSync.swift
//  FinderExt
//
//  Finder Sync Extension 入口：注册全盘监控，提供 MenuPlus 子菜单。
//

import Cocoa
import FinderSync

class FinderSync: FIFinderSync {
    private struct MenuContext {
        var terminalTargets: [URL] = []
        var generalTargets: [URL] = []
        var createFileTargets: [URL] = []
        var newWindowTargets: [URL] = []
    }

    private let controller = FIFinderSyncController.default()
    private var currentMenuContext = MenuContext()

    /// 菜单项图标复用宿主 App 的应用图标：扩展自身没有 Assets，
    /// 而 .appex 固定位于 MenuPlus.app/Contents/PlugIns/ 内，回溯三级即得宿主路径。
    /// static 缓存避免每次弹出菜单都重新取图标。
    private static let menuIcon: NSImage? = {
        let hostAppURL = Bundle.main.bundleURL
            .deletingLastPathComponent() // PlugIns
            .deletingLastPathComponent() // Contents
            .deletingLastPathComponent() // MenuPlus.app
        guard hostAppURL.pathExtension == "app" else { return nil }
        // icon(forFile:) 返回的实例可能被 Icon Services 缓存共享，copy 后再改尺寸避免污染共享对象。
        guard let icon = NSWorkspace.shared.icon(forFile: hostAppURL.path).copy() as? NSImage else {
            return nil
        }
        // NSMenuItem 不会自动缩放图标，需限定为菜单常规的 16x16 点。
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }()

    override init() {
        super.init()

        NSLog("MenuPlus FinderSync 已加载，bundle: %@", Bundle.main.bundlePath as NSString)

        // 监控全盘，使右键菜单在任意路径都可用。
        controller.directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override func beginObservingDirectory(at url: URL) {}
    override func endObservingDirectory(at url: URL) {}
    override func requestBadgeIdentifier(for url: URL) {}

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let context = makeMenuContext(for: menuKind)
        currentMenuContext = context
        let submenu = buildSubmenu(context: context)
        guard !submenu.items.isEmpty else { return nil }

        let menu = NSMenu(title: "")
        let parentItem = NSMenuItem(title: "MenuPlus", action: nil, keyEquivalent: "")
        parentItem.image = Self.menuIcon
        parentItem.submenu = submenu
        menu.addItem(parentItem)
        return menu
    }

    private func makeMenuContext(for menuKind: FIMenuKind) -> MenuContext {
        MenuContext(
            terminalTargets: terminalTargets(for: menuKind),
            generalTargets: generalTargets(for: menuKind),
            createFileTargets: createFileTargets(for: menuKind),
            newWindowTargets: newWindowTargets(for: menuKind)
        )
    }

    private func buildSubmenu(context: MenuContext) -> NSMenu {
        let menu = NSMenu(title: "MenuPlus")

        if !context.terminalTargets.isEmpty {
            menu.addItem(menuItem(
                title: "在终端中打开",
                selector: #selector(actionOpenInTerminal(_:))
            ))
        }

        if !context.generalTargets.isEmpty {
            menu.addItem(menuItem(
                title: "在 VSCode 中打开",
                selector: #selector(actionOpenInVSCode(_:))
            ))
            menu.addItem(menuItem(
                title: "复制路径",
                selector: #selector(actionCopyFullPath(_:))
            ))
            menu.addItem(menuItem(
                title: "复制文件(夹)名",
                selector: #selector(actionCopyFileName(_:))
            ))
        }

        if !context.createFileTargets.isEmpty {
            menu.addItem(menuItem(
                title: "新建文件",
                selector: #selector(actionCreateBlankFile(_:))
            ))
            menu.addItem(menuItem(
                title: "新建 txt 文件",
                selector: #selector(actionCreateTxtFile(_:))
            ))
        }

        if !context.newWindowTargets.isEmpty {
            menu.addItem(menuItem(
                title: "在新窗口打开",
                selector: #selector(actionOpenInNewFinderWindow(_:))
            ))
        }

        return menu
    }

    private func menuItem(title: String, selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
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

    /// 新建文件统一走 IPC 交给主 App 执行（扩展沙盒内直写不稳定，见 spec 第 5 节）：
    /// 明确选中的文件夹直接作为目标；右键空白区域则取当前目录（不含 sidebar，
    /// 避免在用户不可见的目录里创建文件）。
    private func createFileTargets(for menuKind: FIMenuKind) -> [URL] {
        if allSelectedItemsAreFolders() {
            return selectedFolders()
        }

        guard menuKind == .contextualMenuForContainer,
              selectedItems().isEmpty,
              let target = targetedURL(),
              isActionableFolder(target) else {
            return []
        }
        return [target]
    }

    private func newWindowTargets(for menuKind: FIMenuKind) -> [URL] {
        guard menuKind == .contextualMenuForItems, allSelectedItemsAreFolders() else { return [] }
        return selectedFolders()
    }

    @objc private func actionOpenInTerminal(_ sender: AnyObject?) {
        let paths = currentMenuContext.terminalTargets.map(\.path)
        NSLog("[MenuPlus/FinderExt] 点击菜单：在终端中打开，targets=%d", paths.count)
        guard !paths.isEmpty else { return }
        IPCClient.send(IPCRequest(action: .openInTerminal, paths: paths))
    }

    @objc private func actionOpenInVSCode(_ sender: AnyObject?) {
        NSLog("[MenuPlus/FinderExt] 点击菜单：在 VSCode 中打开，targets=%d", currentMenuContext.generalTargets.count)
        for url in currentMenuContext.generalTargets {
            FinderSyncActions.openInVSCode(url: url)
        }
    }

    @objc private func actionCopyFullPath(_ sender: AnyObject?) {
        let paths = currentMenuContext.generalTargets.map(\.path)
        NSLog("[MenuPlus/FinderExt] 点击菜单：复制路径，targets=%d", paths.count)
        guard !paths.isEmpty else { return }
        FinderSyncActions.copyToClipboard(paths.joined(separator: "\n"))
    }

    @objc private func actionCopyFileName(_ sender: AnyObject?) {
        let names = currentMenuContext.generalTargets.map(\.lastPathComponent)
        NSLog("[MenuPlus/FinderExt] 点击菜单：复制文件名，targets=%d", names.count)
        guard !names.isEmpty else { return }
        FinderSyncActions.copyToClipboard(names.joined(separator: "\n"))
    }

    @objc private func actionCreateBlankFile(_ sender: AnyObject?) {
        createFile(action: .createBlankFile)
    }

    @objc private func actionCreateTxtFile(_ sender: AnyObject?) {
        createFile(action: .createTxtFile)
    }

    private func createFile(action: IPCAction) {
        let paths = currentMenuContext.createFileTargets.map(\.path)
        NSLog("[MenuPlus/FinderExt] 点击菜单：%@，targets=%d", action.rawValue, paths.count)
        guard !paths.isEmpty else { return }
        IPCClient.send(IPCRequest(action: action, paths: paths))
    }

    @objc private func actionOpenInNewFinderWindow(_ sender: AnyObject?) {
        let paths = currentMenuContext.newWindowTargets.map(\.path)
        NSLog("[MenuPlus/FinderExt] 点击菜单：在新窗口打开，targets=%d", paths.count)
        guard !paths.isEmpty else { return }
        IPCClient.send(IPCRequest(action: .openInNewFinderWindow, paths: paths))
    }
}
