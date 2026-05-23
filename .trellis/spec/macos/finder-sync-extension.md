# Finder Sync Extension 开发规范

## 1. 架构概述

本项目使用两进程架构：

```
[FinderExt 进程]          [主 App 进程]
    (沙盒 = ON)               (沙盒 = OFF)
         │                         │
         │  rightmenu://           │
         │  openInTerminal         │
         │  ?paths=<base64>        │
         │────────────────────────▶│
         │  NSWorkspace.open(url)  │  IPCExecutor.execute()
         │  (LaunchServices 中转)  │  → Terminal / 创建文件 / etc.
         │                         │  → UNUserNotification（失败时）
```

**为什么这样设计**：FinderSync 扩展必须保持沙盒为 ON（Sequoia + ad-hoc 签名要求）；但沙盒会阻止对外部 App 的 NSWorkspace.open 和文件系统写操作。URL Scheme 是同源 LaunchServices 调用，不受沙盒拦截。

---

## 2. IPC 协议（URL Scheme）

### URL 格式

```
rightmenu://<action>?paths=<base64-encoded-JSON-string-array>
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

    func toURL() -> URL?        // 编码为 rightmenu:// URL
    static func from(url: URL) -> IPCRequest?  // 主 App 端反序列化
}
```

**编码方式**：`paths` 先 JSON encode，再 base64，放入 query item `paths=`。  
原因：文件路径可能含空格、中文、`#`、`&` 等特殊字符，base64 可完全避免 URL 转义问题。

### 扩展端发送（IPCClient）

```swift
// FinderExt/IPCClient.swift
IPCClient.send(IPCRequest(action: .openInTerminal, paths: [url.path]))
// → NSWorkspace.shared.open(rightmenu://openInTerminal?paths=...)
```

### 主 App 端接收（AppDelegate）

```swift
// rightMenuApp.swift — AppDelegate
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
| 打开 URL scheme（同源） | `NSWorkspace.shared.open(url)` | vscode://、rightmenu:// 皆可 |
| 访问 selectedItemURLs() 返回路径 | 有限制，见 3.2 | |

### 3.2 扩展进程内**不可用**（必须走 IPC）

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

---

## 4. Sandbox 必须保持 ON（Sequoia + ad-hoc 签名）

**严禁**将 FinderSync 扩展的沙盒关掉（`app-sandbox = false` 或 `ENABLE_APP_SANDBOX = NO`）。

**症状**：关掉沙盒后右键菜单完全消失，Console 无报错。  
**原因**：macOS Sequoia 上，PluginKit 对 ad-hoc 签名 + `sandbox=false` 的 FinderSync 扩展拒绝注册，且不提供任何错误日志。  
**验证**：`pluginkit -m -p com.apple.FinderSync -v` — 扩展应出现在列表；`pluginkit -e use -i zl.rightMenu.FinderExt` 可强制启用。

---

## 5. 目标选择逻辑

```swift
// FinderSync.swift — selectedTargets()
// 优先用 selectedItemURLs()；右键空白区域时回退到 targetedURL()
private func selectedTargets() -> [URL] {
    if let selected = FIFinderSyncController.default().selectedItemURLs(), !selected.isEmpty {
        return selected
    }
    if let target = FIFinderSyncController.default().targetedURL() {
        return [target]
    }
    return []
}
```

**allSelectedAreFolders 条件**（用于"新建文件"类操作）：
```swift
let selectedURLs = FIFinderSyncController.default().selectedItemURLs() ?? []
let allSelectedAreFolders = !selectedURLs.isEmpty && selectedURLs.allSatisfy { $0.hasDirectoryPath }
```
必须同时满足：非空 + 全是文件夹。空选区（右键空白处）不应触发文件创建。

---

## 6. 双端 IPCAction.swift 同步要求

由于 Xcode 16 的 `FileSystemSynchronizedRootGroup` 不支持跨 target 目录共享源文件，`IPCAction.swift` 在两个 target 目录各放一份（`FinderExt/IPCAction.swift` 和 `rightMenu/IPCAction.swift`）。

> **⚠️ 任何对 IPCAction / IPCRequest 的修改必须同时更新两个文件，否则协议不匹配导致 IPC 静默失败。**

文件头注释已标注此要求：
```swift
// ⚠️ 这个文件必须和 rightMenu/IPCAction.swift（或 FinderExt/IPCAction.swift）保持完全一致
```

---

## 7. 终端打开的正确姿势

**不要用 AppleScript**（在 Terminal 未运行时报 `-600` 错误）：
```swift
// ❌
let script = "tell application \"Terminal\" to do script \"cd '\(path)'\""
```

**使用 NSWorkspace.open(_:withApplicationAt:)** ：
```swift
// ✅ — IPCExecutor.openInTerminal
let terminalURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
let config = NSWorkspace.OpenConfiguration()
NSWorkspace.shared.open(
    [URL(fileURLWithPath: path)],
    withApplicationAt: terminalURL,
    configuration: config
) { _, error in
    if let error = error { notifyFail("在终端打开", error.localizedDescription) }
}
```

---

## 8. 错误处理矩阵

| 场景 | 行为 |
|------|------|
| `IPCRequest.toURL()` 返回 nil | NSLog 记录，静默失败 |
| 主 App 收到无法解析的 URL | NSLog 记录，跳过该 URL |
| `IPCExecutor.execute` paths 为空 | 调用 `notifyFail` + NSLog |
| 文件创建失败（FileManager） | 调用 `notifyFail` 弹通知 |
| NSWorkspace.open 失败（completion error） | 调用 `notifyFail` 弹通知 |
| UNUserNotificationCenter.add 失败 | 仅 NSLog，不再重试 |

---

## 9. 新增 IPC 动作的步骤

1. 在 `FinderExt/IPCAction.swift` 的 `IPCAction` 枚举加新 case
2. **同步** 更新 `rightMenu/IPCAction.swift`（两文件保持一致）
3. 在 `rightMenu/IPCExecutor.swift` 的 `execute()` 的 `switch` 加对应 case
4. 在 `FinderExt/FinderSync.swift` 的 `buildSubmenu()` 加菜单项 + `@objc` handler
5. Handler 调用 `IPCClient.send(IPCRequest(action: .newAction, paths: [...]))`
