# Finder Sync Extension 开发规范

## 1. 架构概述

本项目使用两进程架构：

```
[FinderExt 进程]          [主 App 进程]
    (沙盒 = ON)               (沙盒 = ON)
         │                         │
         │  menuplus://           │
         │  openInTerminal         │
         │  createBlankFile        │
         │  createTxtFile          │
         │  ?paths=<base64>        │
         │────────────────────────▶│
         │  NSWorkspace.open(url)  │  IPCExecutor.execute()
         │  (LaunchServices 中转)  │  → Terminal / 创建文件 / Finder 自动化
         │                         │  → Security-scoped bookmark 授权
         │                         │  → UNUserNotification（失败时）
```

**为什么这样设计**：FinderSync 扩展必须保持沙盒为 ON（Sequoia + ad-hoc 签名要求）；但沙盒会阻止对外部 App 的 NSWorkspace.open 和文件系统写操作。URL Scheme 是同源 LaunchServices 调用，不受沙盒拦截。

---

## 2. IPC 协议（URL Scheme）

### URL 格式

```
menuplus://<action>?paths=<base64-encoded-JSON-string-array>
```

### IPCAction 枚举（两端必须保持完全一致）

```swift
enum IPCAction: String, Codable {
    case openInTerminal
    case createBlankFile
    case createTxtFile
    case openInNewFinderWindow
    // 未来扩展：toggleHiddenFiles 等
}
```

### IPCRequest 签名

```swift
struct IPCRequest {
    let action: IPCAction
    let paths: [String]         // 绝对路径列表

    func toURL() -> URL?        // 编码为 menuplus:// URL
    static func from(url: URL) -> IPCRequest?  // 主 App 端反序列化
}
```

**编码方式**：`paths` 先 JSON encode，再 base64，放入 query item `paths=`。  
原因：文件路径可能含空格、中文、`#`、`&` 等特殊字符，base64 可完全避免 URL 转义问题。

### 扩展端发送（IPCClient）

```swift
// FinderExt/IPCClient.swift
IPCClient.send(IPCRequest(action: .openInTerminal, paths: [url.path]))
// → NSWorkspace.shared.open(menuplus://openInTerminal?paths=...)
```

### 主 App 端接收（AppDelegate）

```swift
// MenuPlusApp.swift — AppDelegate
func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
        guard let request = IPCRequest.from(url: url) else { continue }
        IPCExecutor.execute(request)
    }
}
```

> **注意**：`MenuBarExtra` 的 Scene 不支持 `.onOpenURL`。URL 必须通过 `AppDelegate.application(_:open:)` 接收，不能在 SwiftUI 的 `.onOpenURL` modifier 里处理。

---

## 3. Sandbox 约束清单

### 3.1 扩展进程内可用（无需 IPC）

| 操作 | API | 备注 |
|------|-----|------|
| 写剪贴板 | `NSPasteboard` | 沙盒允许 |
| 打开 URL scheme（同源） | `NSWorkspace.shared.open(url)` | vscode://、menuplus:// 皆可 |
| 访问 selectedItemURLs() 返回路径 | 有限制，见 3.2 | |

### 3.2 扩展进程内**不可用或不稳定**（应优先走 IPC）

| 操作 | 失败表现 | 走 IPC 后解决 |
|------|---------|--------------|
| `NSWorkspace.open` 打开 Terminal.app 等外部应用 | "没有权限打开 XX" | ✅ |
| `FileManager` 在非 user-selected 路径下写文件 | 权限被拒 | ✅ |
| `Process` / `killall Finder` 等 shell | 直接崩溃/被拒 | ✅ |
| `UNUserNotificationCenter` | 崩溃，见 3.3 | ✅（主 App 代发） |

### 3.3 UNUserNotificationCenter 在扩展进程崩溃

**症状**：调用 `UNUserNotificationCenter.current()` 立即崩溃：
```
NSInternalInconsistencyException: 'application bundle identifier for LSPlugInKitProxy'
```

**原因**：`UNUserNotificationCenter` 要求调用方是有 bundle ID 的 App 进程。Finder Sync Extension 以 `LSPlugInKitProxy` 为宿主运行，没有标准 App bundle 标识。

**解决**：完全移除扩展内的所有 `UNUserNotificationCenter` 使用。失败通知通过 IPC 转给主 App 发送。

```swift
// ❌ 在扩展进程里这样写会崩溃
UNUserNotificationCenter.current().add(req)

// ✅ 应该通过 IPC 转给主 App，主 App 里的 IPCExecutor.notifyFail 代发
IPCClient.send(IPCRequest(action: .someAction, paths: [...]))
// 主 App 执行失败时自行调用 UNUserNotificationCenter
```

### 3.4 selectedItemURLs() 的 sandbox 权限范围

`selectedItemURLs()` 返回的路径**不自动授予** sandbox 的 `NSWorkspace.open` 权限。

```swift
// ❌ 以下代码在沙盒中会被拒绝，即使 url 来自 selectedItemURLs()
NSWorkspace.shared.open([url], withApplicationAt: terminalURL, configuration: config)

// ✅ 通过 IPC 发给无沙盒的主 App 执行
IPCClient.send(IPCRequest(action: .openInTerminal, paths: [url.path]))
```

### 3.5 主 App 的 security-scoped bookmark 持久化

Finder 空白区域的“新建文件 / 新建 txt 文件”以及“在终端打开”如果要对当前目录复用一次授权，主 App 不能只依赖临时 `NSOpenPanel` 返回值；必须把授权目录持久化为 **security-scoped bookmark**。

**当前项目约定**：
- 使用 `URL.bookmarkData(options: [.withSecurityScope], ...)` 生成 bookmark
- 使用主 App 沙盒内的 `UserDefaults.standard` 持久化 `[String: Data]`
- key 必须是标准化后的绝对路径（`standardizedFileURL.path`）
- 执行目录动作时，必须优先查找“最长前缀匹配”的已授权目录；父目录 bookmark 可覆盖其全部子目录
- 每次执行前先尝试 `URL(resolvingBookmarkData:options:[.withSecurityScope], ...)`
- `startAccessingSecurityScopedResource()` 返回 `false` 时，视为缓存失效，删除旧 bookmark 并重新请求授权
- 设置页允许用户预先添加多个常用目录；这些目录与运行时弹窗授权得到的 bookmark 使用同一份存储与复用逻辑

> **Warning**: 如果 bookmark 已经创建，但主 App 仍然每次都弹 `NSOpenPanel`，先检查是不是“新二进制已覆盖 /Applications，但旧 MenuPlus 进程还没退出”。Finder 扩展通过 URL Scheme 唤起时，LaunchServices 可能继续把 IPC 发给旧进程，导致你误以为新代码未生效。

> **Warning**: 不要只按“目标目录全路径完全相等”查 bookmark。正确行为是：先命中最近的祖先授权目录，再在该 security scope 下拼出目标子目录 URL。

---

## 4. Sandbox 必须保持 ON（Sequoia + ad-hoc 签名）

**严禁**将 FinderSync 扩展的沙盒关掉（`app-sandbox = false` 或 `ENABLE_APP_SANDBOX = NO`）。

**症状**：关掉沙盒后右键菜单完全消失，Console 无报错。  
**原因**：macOS Sequoia 上，PluginKit 对 ad-hoc 签名 + `sandbox=false` 的 FinderSync 扩展拒绝注册，且不提供任何错误日志。  
**验证**：`pluginkit -m -p com.apple.FinderSync -v` — 扩展应出现在列表；`pluginkit -e use -i zl.MenuPlus.FinderExt` 可强制启用。

---
### 4.1 主 App 应显式检查 Finder 扩展启用状态

主 App 不应只依赖一次性的 onboarding 弹窗或私有 URL deep link。优先使用 FinderSync 官方接口：

```swift
FIFinderSyncController.isExtensionEnabled
FIFinderSyncController.showExtensionManagementInterface()
```

**契约**：
- App 启动 / 回到前台时刷新 `isExtensionEnabled`。
- 未启用时，在菜单栏菜单和设置页都要给出明确状态与“立即启用”入口。
- 调起扩展管理界面后，用户返回 App 时再次刷新状态。

> **Warning**: 构建产物路径改变（例如从 `/Applications` 切到 Xcode DerivedData）后，PluginKit 可能把新 bundle 视为新的扩展实例。不要假设“以前启用过一次”就永远有效。

---

## 5. 目标选择逻辑

### Scenario: Finder 菜单目标选择、空白区域创建与权限边界

#### 1. Scope / Trigger
- Trigger: 修改 Finder 右键菜单显示规则、目标路径选择逻辑或“新建文件”权限判断时。

#### 2. Signatures
- `override func menu(for menuKind: FIMenuKind) -> NSMenu?`
- `selectedItemURLs() -> [URL]?`
- `targetedURL() -> URL?`

#### 3. Contracts
- `selectedItemURLs()`：仅表示“明确选中的条目”。
- `targetedURL()`：可用于右键空白区域 / sidebar 的上下文目录，但**不等价**于用户显式选中。
- `FIMenuKind.contextualMenuForItems`：右键选中项。
- `FIMenuKind.contextualMenuForContainer`：右键 Finder 窗口空白区域。
- Finder 空白区域的“新建文件 / 新建 txt 文件”必须走：`FinderExt → IPC → MenuPlus 主 App → NSOpenPanel / security-scoped bookmark → FileManager.createFile`。
- 明确选中的文件夹可由 FinderExt 直接创建文件；空白区域当前目录不能假定拥有 `user-selected` 写权限。

#### 4. Validation & Error Matrix
- `selectedItemURLs().isEmpty && menuKind == .contextualMenuForContainer` → 允许“在终端打开 / 在 VSCode 中打开 / 复制路径 / 新建文件 / 新建 txt 文件”等动作，但“新建*”必须通过 IPC 交给主 App 授权后执行。
- `selectedItemURLs()` 非空且全部为文件夹 → 可显示“新建文件 / 新建 txt 文件 / 在新窗口打开”；其中“新建*”可由扩展直接创建。
- 混合选择文件 + 文件夹 → 不显示仅目录动作。
- 已授权 `/A`，当前目标是 `/A/B/C` → 主 App 必须直接复用 `/A` 的 bookmark，不再弹授权面板。
- 用户在主 App 授权面板点取消 → 不创建文件，并给出“下次再次执行会重新弹出授权面板”的提示。
- 用户在授权面板选错目录 → 不创建文件，并明确要求选择当前 Finder 目录本身。

#### 5. Good / Base / Bad Cases
- Good: 右键空白区域，显示“新建文件 / 新建 txt 文件”，点击后主 App 弹目录授权面板，授权成功后创建文件。
- Good: 在设置页预先授权 `/Projects` 后，右键 `/Projects/Foo/Bar` 空白区域执行“新建文件”，应直接成功且不再弹授权面板。
- Base: 右键单个文件夹，扩展直接创建“新建文件 / 新建 txt 文件”，无需额外弹窗。
- Bad: 空白区域沿用扩展内 `FileManager.createFile` 直接写，结果因缺少写权限失败。

#### 6. Tests Required
- 右键文件夹图标：应显示“新建文件 / 新建 txt 文件 / 在新窗口打开”。
- 右键 Finder 空白区域：应显示“新建文件 / 新建 txt 文件”，且首次点击会出现目录授权面板。
- 先授权父目录，再操作任意子目录：不应再次出现授权面板。
- 设置页添加授权目录后，重新打开设置页：授权列表应持久化显示。
- 选中文件后右键：不应显示目录专属动作。
- 在授权面板点取消：不创建文件，并只出现一次失败提示。

#### 7. Wrong vs Correct
##### Wrong
```swift
let targets = selectedItemURLs() ?? [targetedURL()].compactMap { $0 }
for target in targets {
    FinderSyncActions.createFile(inDirectory: target.path, baseName: "新建文件", extension: nil)
}
```

##### Correct
```swift
let selected = selectedItemURLs() ?? []
let allSelectedAreFolders = !selected.isEmpty && selected.allSatisfy { $0.hasDirectoryPath }

if menuKind == .contextualMenuForContainer, let target = targetedURL() {
    IPCClient.send(IPCRequest(action: .createBlankFile, paths: [target.path]))
} else {
    for folder in selected where folder.hasDirectoryPath {
        FinderSyncActions.createFile(inDirectory: folder.path, baseName: "新建文件", extension: nil)
    }
}
```

---

## 6. 双端 IPCAction.swift 同步要求

由于 Xcode 16 的 `FileSystemSynchronizedRootGroup` 不支持跨 target 目录共享源文件，`IPCAction.swift` 在两个 target 目录各放一份（`FinderExt/IPCAction.swift` 和 `MenuPlus/IPCAction.swift`）。

> **⚠️ 任何对 IPCAction / IPCRequest 的修改必须同时更新两个文件，否则协议不匹配导致 IPC 静默失败。**

文件头注释已标注此要求：
```swift
// ⚠️ 这个文件必须和 MenuPlus/IPCAction.swift（或 FinderExt/IPCAction.swift）保持完全一致
```

---

## 7. 终端打开的正确姿势

**不要用 AppleScript**（在 Terminal 未运行时报 `-600` 错误）：
```swift
// ❌
let script = "tell application \"Terminal\" to do script \"cd '\(path)'\""
```

**使用带 security scope 的 `NSWorkspace.open(_:withApplicationAt:)`** ：
```swift
// ✅ — IPCExecutor.openInTerminal
let terminalURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
let config = NSWorkspace.OpenConfiguration()
try SecurityScopedDirectoryStore.withAccess(to: path, actionName: "在终端打开") { directoryURL in
    NSWorkspace.shared.open(
        [directoryURL],
        withApplicationAt: terminalURL,
        configuration: config
    ) { _, error in
        if let error { notifyFail("在终端打开", error.localizedDescription) }
    }
}
```

**不要把设置窗口作为普通 `Window` 在 IPC 唤起链路里自动恢复出来**：
```swift
// ❌ URL Scheme 唤起主 App 时，普通 Window scene 可能一起弹出
Window("MenuPlus 设置", id: "settings") { ContentView() }

// ✅ 设置页用 Settings scene，仅用户主动点“设置…”时打开
Settings { ContentView() }
```

---

## 8. 错误处理矩阵

| 场景 | 行为 |
|------|------|
| `IPCRequest.toURL()` 返回 nil | NSLog 记录，静默失败 |
| 主 App 收到无法解析的 URL | NSLog 记录，跳过该 URL |
| `IPCExecutor.execute` paths 为空 | 调用 `notifyFail` + NSLog |
| 文件创建失败（FileManager） | 调用 `notifyFail` 弹通知 |
| 用户取消目录授权 | 只弹一次失败提示，说明下次会再次请求授权 |
| 用户选错目录授权 | 只弹一次失败提示，明确要求选中当前 Finder 目录 |
| NSWorkspace.open 失败（completion error） | 调用 `notifyFail` 弹通知 |
| UNUserNotificationCenter.add 失败 | 仅 NSLog，不再重试 |

---

## 9. 新增 IPC 动作的步骤

1. 在 `FinderExt/IPCAction.swift` 的 `IPCAction` 枚举加新 case
2. **同步** 更新 `MenuPlus/IPCAction.swift`（两文件保持一致）
3. 在 `MenuPlus/IPCExecutor.swift` 的 `execute()` 的 `switch` 加对应 case
4. 在 `FinderExt/FinderSync.swift` 的 `buildSubmenu()` 加菜单项 + `@objc` handler
5. Handler 调用 `IPCClient.send(IPCRequest(action: .newAction, paths: [...]))`
6. 如果动作涉及 Finder 空白区域写入，再补 `SecurityScopedDirectoryStore` 授权链路
