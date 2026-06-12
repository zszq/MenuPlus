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
        /// 自定义"用 XX 打开"应用列表，每次构建菜单时从共享配置读取
        var openWithApps: [OpenWithApp] = []
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

    /// "MenuPlus新建" 顶层菜单图标：SF Symbol plus.square，延续"扩展不放图标资源"的约定。
    /// 必须预先光栅化成位图再交给 NSMenuItem：FinderSync 菜单要跨进程序列化给 Finder 渲染，
    /// symbol 原始图像（含绘制闭包/矢量描述）序列化后可能丢内容，位图最可靠。
    /// 同时 isTemplate = true 让菜单按深/浅色自动着色——这是深色模式下图标跟随文字变色的关键。
    /// 任一步失败返回 nil（不设图标），不崩溃。
    private static let createMenuIcon: NSImage? = {
        // pointSize 取 14：在 16x16 点的菜单图标槽里留出边距，线条不贴边、不发糊
        guard let symbol = NSImage(systemSymbolName: "plus.square", accessibilityDescription: "新建文件")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)) else {
            return nil
        }

        let targetSize = NSSize(width: 16, height: 16)
        let image = NSImage(size: targetSize)

        // 1x（16px）与 2x（32px）两个 rep 都要，保证 Retina 下清晰
        for scale in [1, 2] {
            let pixels = 16 * scale
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixels,
                pixelsHigh: pixels,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ) else { return nil }
            // 点尺寸固定 16x16，像素更高的 rep 即成为 2x representation
            rep.size = targetSize

            // 不用 NSImage(size:flipped:drawingHandler:)：其绘制闭包无法跨进程执行，
            // 序列化给 Finder 后可能丢内容；这里显式把 symbol 画进 bitmap rep
            guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            let symbolSize = symbol.size
            // 在 16x16 点的画布内居中
            let origin = NSPoint(
                x: (targetSize.width - symbolSize.width) / 2,
                y: (targetSize.height - symbolSize.height) / 2
            )
            symbol.draw(in: NSRect(origin: origin, size: symbolSize))
            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()

            image.addRepresentation(rep)
        }

        // 模板图像：菜单绘制时按当前外观（深/浅色）自动着色
        image.isTemplate = true
        image.accessibilityDescription = "新建文件"
        return image
    }()

    override init() {
        super.init()

        NSLog("MenuPlus FinderSync 已加载，bundle: %@", Bundle.main.bundlePath as NSString)

        // 监控全盘，使右键菜单在任意路径都可用。
        controller.directoryURLs = [URL(fileURLWithPath: "/")]

        // 诊断日志：读真实 home 共享配置依赖 temporary-exception entitlement（签名/路径不匹配会静默失效），
        // 启动即读一次并打印结果，部署后可用 log show 确认链路是否通（失败原因由 load 内部分类打印）。
        NSLog("[MenuPlus/FinderExt] 启动读取共享配置：openWithApps=%d", ExtensionConfigReader.load().count)
    }

    override func beginObservingDirectory(at url: URL) {}
    override func endObservingDirectory(at url: URL) {}
    override func requestBadgeIdentifier(for url: URL) {}

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let context = makeMenuContext(for: menuKind)
        currentMenuContext = context

        let menu = NSMenu(title: "")

        // "MenuPlus"：通用动作子菜单（新建类已迁移到 "MenuPlus新建"）
        let submenu = buildSubmenu(context: context)
        if !submenu.items.isEmpty {
            let parentItem = NSMenuItem(title: "MenuPlus", action: nil, keyEquivalent: "")
            parentItem.image = Self.menuIcon
            parentItem.submenu = submenu
            menu.addItem(parentItem)
        }

        // "MenuPlus新建"：与 "MenuPlus" 同级的新建模板菜单，无创建目标时不显示
        if let createSubmenu = buildCreateSubmenu(context: context) {
            let createItem = NSMenuItem(title: "MenuPlus新建", action: nil, keyEquivalent: "")
            createItem.image = Self.createMenuIcon
            createItem.submenu = createSubmenu
            menu.addItem(createItem)
        }

        return menu.items.isEmpty ? nil : menu
    }

    private func makeMenuContext(for menuKind: FIMenuKind) -> MenuContext {
        MenuContext(
            terminalTargets: terminalTargets(for: menuKind),
            generalTargets: generalTargets(for: menuKind),
            createFileTargets: createFileTargets(for: menuKind),
            newWindowTargets: newWindowTargets(for: menuKind),
            // 每次右键都经 load() 取最新配置，设置页改动即时生效；
            // load 内部有 mtime+size 缓存，文件未变时不重复读盘解码（右键是阻塞 UI 的热路径）
            openWithApps: ExtensionConfigReader.load()
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
            // 自定义"用 XX 打开"（VSCode 不再硬编码：主 App 首次启动检测到已安装时
            // 会自动 seed 进该列表，统一走通用机制）。
            // FinderSync 菜单跨进程序列化回 Finder，representedObject 不可靠，
            // 用 tag 存 openWithApps 下标做映射（同模板菜单的 tag 模式）。
            for (index, app) in context.openWithApps.enumerated() {
                let item = menuItem(
                    title: "用 \(app.name) 打开",
                    selector: #selector(actionOpenWithApp(_:))
                )
                item.tag = index
                menu.addItem(item)
            }

            menu.addItem(menuItem(
                title: "复制路径",
                selector: #selector(actionCopyFullPath(_:))
            ))
            menu.addItem(menuItem(
                title: "复制文件(夹)名",
                selector: #selector(actionCopyFileName(_:))
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

    /// 构建 "MenuPlus新建" 子菜单；无可创建目标时返回 nil（顶层项随之隐藏）。
    private func buildCreateSubmenu(context: MenuContext) -> NSMenu? {
        guard !context.createFileTargets.isEmpty else { return nil }

        let menu = NSMenu(title: "MenuPlus新建")
        menu.addItem(menuItem(
            title: "空白文件",
            selector: #selector(actionCreateBlankFile(_:))
        ))
        menu.addItem(menuItem(
            title: "文本文件",
            selector: #selector(actionCreateTxtFile(_:))
        ))

        // 模板项紧随其后不加分隔线，整组按 allCases 声明顺序排列。
        // FinderSync 菜单要跨进程序列化回 Finder，representedObject 不可靠，
        // 用 tag 存 allCases 下标做模板映射。
        for (index, template) in FileTemplate.allCases.enumerated() {
            let item = menuItem(
                title: template.menuTitle,
                selector: #selector(actionCreateFromTemplate(_:))
            )
            item.tag = index
            menu.addItem(item)
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

    @objc private func actionOpenWithApp(_ sender: AnyObject?) {
        // tag 即 openWithApps 下标（见 buildSubmenu），越界直接忽略
        let apps = currentMenuContext.openWithApps
        guard let item = sender as? NSMenuItem, apps.indices.contains(item.tag) else { return }
        let app = apps[item.tag]

        let paths = currentMenuContext.generalTargets.map(\.path)
        NSLog("[MenuPlus/FinderExt] 点击菜单：用 %@ 打开，targets=%d", app.name, paths.count)
        guard !paths.isEmpty else { return }
        IPCClient.send(IPCRequest(action: .openWithApp, paths: paths, appPath: app.path))
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

    @objc private func actionCreateFromTemplate(_ sender: AnyObject?) {
        // tag 即 FileTemplate.allCases 下标（见 buildCreateSubmenu），越界直接忽略
        let templates = FileTemplate.allCases
        guard let item = sender as? NSMenuItem, templates.indices.contains(item.tag) else { return }
        let template = templates[item.tag]

        let paths = currentMenuContext.createFileTargets.map(\.path)
        NSLog("[MenuPlus/FinderExt] 点击菜单：新建 %@，targets=%d", template.menuTitle, paths.count)
        guard !paths.isEmpty else { return }
        IPCClient.send(IPCRequest(action: .createFromTemplate, paths: paths, templateID: template.rawValue))
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
