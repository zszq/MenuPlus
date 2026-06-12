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
        var selectedCreatableFolders: [URL] = []
        var containerCreatableTarget: URL?
        var newWindowTargets: [URL] = []
    }

    private enum CreateFileMode: Int {
        case directSelection = 1
        case authorizedContainer = 2
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

    override var toolbarItemName: String { "MenuPlus" }
    override var toolbarItemToolTip: String { "MenuPlus 右键菜单扩展" }
    override var toolbarItemImage: NSImage {
        NSImage(systemSymbolName: "filemenu.and.cursorarrow", accessibilityDescription: nil)
            ?? NSImage(named: NSImage.actionTemplateName)!
    }

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
            selectedCreatableFolders: selectedCreatableFolders(),
            containerCreatableTarget: containerCreatableTarget(for: menuKind),
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

        if !context.selectedCreatableFolders.isEmpty {
            menu.addItem(menuItem(
                title: "新建文件",
                selector: #selector(actionCreateBlankFile(_:)),
                tag: CreateFileMode.directSelection.rawValue
            ))
            menu.addItem(menuItem(
                title: "新建 txt 文件",
                selector: #selector(actionCreateTxtFile(_:)),
                tag: CreateFileMode.directSelection.rawValue
            ))
        } else if context.containerCreatableTarget != nil {
            menu.addItem(menuItem(
                title: "新建文件",
                selector: #selector(actionCreateBlankFile(_:)),
                tag: CreateFileMode.authorizedContainer.rawValue
            ))
            menu.addItem(menuItem(
                title: "新建 txt 文件",
                selector: #selector(actionCreateTxtFile(_:)),
                tag: CreateFileMode.authorizedContainer.rawValue
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

    private func menuItem(title: String, selector: Selector, tag: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        item.tag = tag
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

    /// 明确选中的文件夹可由扩展直接写；右键空白区域的当前目录则要交给主 App 走授权。
    private func selectedCreatableFolders() -> [URL] {
        guard allSelectedItemsAreFolders() else { return [] }
        return selectedFolders()
    }

    private func containerCreatableTarget(for menuKind: FIMenuKind) -> URL? {
        guard menuKind == .contextualMenuForContainer,
              selectedItems().isEmpty,
              let target = targetedURL(),
              isActionableFolder(target) else {
            return nil
        }
        return target
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
        createFile(from: sender, action: .createBlankFile, fileExtension: nil)
    }

    @objc private func actionCreateTxtFile(_ sender: AnyObject?) {
        createFile(from: sender, action: .createTxtFile, fileExtension: "txt")
    }

    private func createFile(from sender: AnyObject?, action: IPCAction, fileExtension: String?) {
        let selectedFolders = currentMenuContext.selectedCreatableFolders
        let containerTarget = currentMenuContext.containerCreatableTarget
        let paths: [String]

        if !selectedFolders.isEmpty {
            paths = selectedFolders.map(\.path)
            NSLog("[MenuPlus/FinderExt] 点击菜单：%@，mode=ipcSelection，targets=%d", action.rawValue, paths.count)
        } else if let containerTarget {
            paths = [containerTarget.path]
            NSLog("[MenuPlus/FinderExt] 点击菜单：%@，mode=authorizedContainer", action.rawValue)
        } else {
            return
        }

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
