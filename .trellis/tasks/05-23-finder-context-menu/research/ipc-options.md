# IPC 通道对比：Extension ↔ Main App

**目的**：对比 5 种 macOS 进程间通信方案在 ad-hoc 签名 + 本地分发场景下的可行性，给出选型推荐与最小可行伪代码骨架。

## 一、对比总表

| 方案 | 需 Apple Dev 账号 | 需 App Group | Payload 大小 | 同步/异步 | 能唤醒主 App | 主 App 未启动可用 | 实现复杂度 |
|---|---|---|---|---|---|---|---|
| **NSXPCConnection (mach service)** | 否 | 否（但常配合 LaunchAgent） | 任意（NSCoding 对象） | 双向异步 | 是（mach 注册触发） | 是 | 高 |
| **CFNotificationCenter Darwin** | 否 | 否 | **0 字节**（仅 name） | 单向异步 | 否 | 否（无人监听） | 低 |
| **NSDistributedNotificationCenter** | 否 | 否 | 小（dict，几 KB） | 单向异步 | 否 | 否 | 低 |
| **App Group + `UserDefaults(suiteName:)`** | 否（按 `app-group-ad-hoc-signing.md` 结论） | **是** | 中（plist，建议 < 1MB） | 异步，需轮询或配合通知 | 否 | 是（写入持久化） | 中 |
| **App Group + 共享文件 (JSON 队列)** | 否（同上） | **是** | 大（无硬上限） | 异步，需通知或轮询 | 否 | 是（持久化队列） | 中 |
| **URL Scheme + Darwin Notif（平替 B）** | 否 | 否 | URL 长度上限（~2KB 实用） | 单向异步 | **是**（`NSWorkspace.open` 唤起主 App） | 是 | 低-中 |

## 二、逐项分析

### 1. NSXPCConnection (mach service)

**机制**：主 App 注册一个 mach service name（通过 `launchd` plist 或 `NSXPCListener(machServiceName:)`），
Extension 用 `NSXPCConnection(machServiceName:options:)` 连接。

**优点**：
- 强类型协议（`NSXPCInterface` 基于 `@objc protocol`）
- 双向通信，支持 reply block
- 主 App 未启动时，如果用 `launchd` LaunchAgent 注册了 `MachServices`，**第一次连接会唤醒主 App**

**缺点**：
- ad-hoc 场景下，mach service 注册比较麻烦：需要
  1. 主 App 装一个 `~/Library/LaunchAgents/zl.rightMenu.helper.plist`
  2. plist 里声明 `MachServices` 字典
  3. `launchctl load`
- LaunchAgent 路径的 plist 必须用绝对路径指向主 App 二进制
- Extension 在 sandbox 下能否 connect 任意 mach name 受 entitlement 限制：需要 `com.apple.security.temporary-exception.mach-lookup.global-name`（**deprecated 但仍可用**）或者主 App 把 mach service 注册到 App Group 的 group container 名下

**结论**：功能最强但实施成本高，**不推荐作为首选**。如果未来要做大量数据传输（比如同步设置）再考虑。

#### 伪代码骨架

```swift
// 共享：定义协议
@objc protocol RightMenuAgentProtocol {
    func openInTerminal(path: String, reply: @escaping (Bool, String?) -> Void)
    func openInVSCode(path: String, reply: @escaping (Bool, String?) -> Void)
    func restartFinder(reply: @escaping (Bool) -> Void)
}

// 主 App: 启动监听
let listener = NSXPCListener(machServiceName: "zl.rightMenu.helper")
listener.delegate = self
listener.resume()

// 主 App: delegate
func listener(_ listener: NSXPCListener, shouldAcceptNewConnection conn: NSXPCConnection) -> Bool {
    conn.exportedInterface = NSXPCInterface(with: RightMenuAgentProtocol.self)
    conn.exportedObject = RightMenuAgent()
    conn.resume()
    return true
}

// Extension: 调用
let conn = NSXPCConnection(machServiceName: "zl.rightMenu.helper")
conn.remoteObjectInterface = NSXPCInterface(with: RightMenuAgentProtocol.self)
conn.resume()
let proxy = conn.remoteObjectProxy as? RightMenuAgentProtocol
proxy?.openInTerminal(path: url.path) { ok, err in
    if !ok { NSLog("远端失败: \(err ?? "")") }
}
```

### 2. CFNotificationCenter Darwin Notification

**机制**：内核级通知中心，纯字符串 name 广播，**不能带 payload**。

**优点**：
- 无 entitlement 要求，sandbox 下也能用
- 极轻量，延迟 < 1ms

**缺点**：
- 不能传数据，只能传"事件发生了"
- 主 App 必须**已在跑**才能收到，进程退出时通知丢失
- 不能唤醒主 App

**用法**：**只适合作为"信号"** 配合其他通道传 payload。例如：
- App Group 共享文件写入 payload → Darwin Notif 通知"有新请求"
- URL Scheme 唤起主 App 后用 Darwin Notif 做 ack

#### 伪代码骨架

```swift
// 发送方
let name = "zl.rightMenu.request" as CFString
CFNotificationCenterPostNotification(
    CFNotificationCenterGetDarwinNotifyCenter(),
    CFNotificationName(name),
    nil, nil, true
)

// 接收方（C 回调，不能捕获 Swift context）
let observer = Unmanaged.passUnretained(self).toOpaque()
CFNotificationCenterAddObserver(
    CFNotificationCenterGetDarwinNotifyCenter(),
    observer,
    { (_, observer, name, _, _) in
        guard let observer = observer else { return }
        let mySelf = Unmanaged<MyClass>.fromOpaque(observer).takeUnretainedValue()
        mySelf.handleNotification()
    },
    "zl.rightMenu.request" as CFString,
    nil,
    .deliverImmediately
)
```

### 3. NSDistributedNotificationCenter

**机制**：用户级通知中心，可带 userInfo dict。

**优点**：
- 能带 payload（plist 兼容类型）
- API 简单

**缺点**：
- macOS 10.14+ sandbox 下 distributed notification 的 payload 默认被剥离（隐私加固），
  对带 payload 的场景不可靠
- 同样无法唤醒主 App

**结论**：**不推荐**。Darwin Notification 更轻，App Group 文件更可靠。

### 4. App Group + `UserDefaults(suiteName:)`

**机制**：两端都 `UserDefaults(suiteName: "group.zl.rightMenu")`，读写共享 plist。

**优点**：
- API 极简
- 持久化（主 App 未启动也能写入排队）
- 支持 KVO（但跨进程 KVO 不可靠，需配合 Darwin Notif）

**缺点**：
- 不适合做"请求队列"（plist 不是队列结构，并发写会冲突）
- 不能区分单个请求的状态

**用法**：**只用来共享配置 / 一次性状态**，不要塞请求队列。

### 5. App Group + 共享文件（JSON 队列）

**机制**：在 group container 下建 `requests/` 目录，Extension 写 JSON 文件作为请求，
主 App 启动后扫描并处理。

**优点**：
- 持久化，主 App 未启动时请求不丢
- 文件原子写（`FileManager.replaceItem` / `NSData.write(atomically: true)`）天然单写者安全
- 支持完整 payload

**缺点**：
- 需要清理已处理文件
- 状态机稍复杂（pending / processing / done / failed）

**这是首选方案**。详见 § 三推荐方案。

### 6. URL Scheme + Darwin Notif（平替 B）

**机制**：主 App 注册 `rightmenu://` URL scheme。Extension 用 `NSWorkspace.shared.open(URL(string: "rightmenu://action?..."))` 唤起主 App，参数走 query string。

**优点**：
- **不依赖 App Group**（适合 App Group 走不通时降级）
- `NSWorkspace.open(URL)` 在 Extension sandbox 下**允许**（这是标准能力，FinderSync 文档明确允许打开 URL）
- 主 App 未启动时**会被自动启动**（LaunchServices 行为）

**缺点**：
- URL 长度限制（实用上限约 2KB）
- 每次都让主 App 弹出来（虽然 `LSUIElement=YES` 不会显示 Dock，但仍触发激活），UX 上有"闪一下"的感觉
- 主 App 用 `NSAppleEventManager` 或 SwiftUI 的 `onOpenURL` 接收

#### 伪代码骨架

```swift
// 主 App: 注册 URL scheme（Info.plist）
// CFBundleURLTypes: [{ CFBundleURLName: "zl.rightMenu", CFBundleURLSchemes: ["rightmenu"] }]

// 主 App: SwiftUI 接收
.onOpenURL { url in
    RequestRouter.handle(url)
}
// 或 AppKit
NSAppleEventManager.shared().setEventHandler(
    self,
    andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
    forEventClass: AEEventClass(kInternetEventClass),
    andEventID: AEEventID(kAEGetURL)
)

// Extension: 发送
var comp = URLComponents()
comp.scheme = "rightmenu"
comp.host = "openInTerminal"
comp.queryItems = [URLQueryItem(name: "path", value: url.path)]
NSWorkspace.shared.open(comp.url!)
```

## 三、推荐方案（综合）

### 主推荐：**App Group + 共享文件（JSON 队列）+ Darwin Notification 唤起**

理由：
- payload 完整、持久化、与 sandbox 兼容
- Darwin Notif 做"即时唤醒"，主 App 在跑时立即处理
- 主 App 未跑时请求落盘，下次启动批量处理（配合 LaunchAgent 让主 App 常驻见 `wakeup-strategy.md`）

### 备选 1：**URL Scheme + Darwin Notif**（如果 App Group 走不通）

理由：完全不依赖 App Group，能唤醒主 App，UX 上"闪一下"在 menu bar 类 App 上可以接受。

### 备选 2：**NSXPCConnection**（如果未来需要双向高频通信）

理由：类型安全、双向，但 ad-hoc + LaunchAgent 配置工作量大，MVP 阶段不值得。

## 四、推荐方案的完整伪代码骨架

### 共享：请求模型（双方共用）

```swift
// SharedTypes.swift（建议放到一个 framework target 或两端各复制一份）
struct IPCRequest: Codable {
    let id: String              // UUID
    let action: Action          // 见下
    let payload: [String: String]  // action 特定参数
    let createdAt: Date

    enum Action: String, Codable {
        case openInTerminal
        case openInVSCode
        case createBlankFile
        case createTxtFile
        case openInNewFinderWindow
        case toggleHiddenFiles
    }
}

struct IPCResponse: Codable {
    let requestId: String
    let success: Bool
    let errorMessage: String?
    let completedAt: Date
}
```

### Extension 端：发送请求

```swift
enum IPCClient {
    static let groupId = "group.zl.rightMenu"
    static let notifName = "zl.rightMenu.newRequest" as CFString

    static var requestsDir: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupId)?
            .appendingPathComponent("requests", isDirectory: true)
    }

    static func send(_ request: IPCRequest) {
        guard let dir = requestsDir else {
            NSLog("[rightMenu] App Group 不可用，IPC 降级")
            sendViaURLScheme(request)  // 降级路径
            return
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(request.id).json")
        let data = try! JSONEncoder().encode(request)
        try? data.write(to: file, options: .atomic)

        // 主 App 在跑时立即处理；未跑时下次启动扫描
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(notifName),
            nil, nil, true
        )
    }

    private static func sendViaURLScheme(_ request: IPCRequest) {
        var c = URLComponents()
        c.scheme = "rightmenu"
        c.host = request.action.rawValue
        c.queryItems = request.payload.map { URLQueryItem(name: $0.key, value: $0.value) }
        if let url = c.url {
            NSWorkspace.shared.open(url)
        }
    }
}
```

### 主 App 端：监听 + 执行 + 回报

```swift
final class IPCServer {
    static let shared = IPCServer()
    private let queue = DispatchQueue(label: "zl.rightMenu.ipcServer")

    func start() {
        // 1. 启动时扫一遍积压
        queue.async { self.drainPending() }

        // 2. 注册 Darwin 通知
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer,
            { (_, ob, _, _, _) in
                guard let ob = ob else { return }
                let s = Unmanaged<IPCServer>.fromOpaque(ob).takeUnretainedValue()
                s.queue.async { s.drainPending() }
            },
            IPCClient.notifName,
            nil,
            .deliverImmediately
        )

        // 3. URL Scheme 兜底（降级路径）
        // 在 AppDelegate 的 application(_:open:) 或 SwiftUI .onOpenURL 里调用
        // IPCServer.shared.handleURLSchemeRequest(url)
    }

    private func drainPending() {
        guard let dir = IPCClient.requestsDir,
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }

        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let req = try? JSONDecoder().decode(IPCRequest.self, from: data)
            else {
                try? FileManager.default.removeItem(at: file)  // 坏数据扔掉
                continue
            }
            execute(req)
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func execute(_ req: IPCRequest) {
        var success = true
        var errMsg: String? = nil
        do {
            switch req.action {
            case .openInTerminal:    try executeOpenTerminal(req.payload)
            case .openInVSCode:      try executeOpenVSCode(req.payload)
            case .createBlankFile:   try executeCreateFile(req.payload, ext: nil)
            case .createTxtFile:     try executeCreateFile(req.payload, ext: "txt")
            case .openInNewFinderWindow: try executeOpenNewWindow(req.payload)
            case .toggleHiddenFiles: try executeToggleHidden()
            }
        } catch {
            success = false
            errMsg = error.localizedDescription
        }
        report(IPCResponse(requestId: req.id, success: success, errorMessage: errMsg, completedAt: Date()))
    }

    private func report(_ resp: IPCResponse) {
        // 见 failure-reporting.md：主 App 直接弹 UNUserNotificationCenter
        // 不需要回写文件给 Extension（Extension 通常已经看不到了）
        if !resp.success {
            FailureNotifier.show(message: resp.errorMessage ?? "未知错误")
        }
    }
}
```

### 主 App AppDelegate：连接

```swift
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        IPCServer.shared.start()
        // ... 原有 onboarding 逻辑
    }
}
```

### Extension 接入点改造

```swift
// FinderSyncActions.swift 改造示例
static func openInTerminal(url: URL) {
    IPCClient.send(IPCRequest(
        id: UUID().uuidString,
        action: .openInTerminal,
        payload: ["path": url.path],
        createdAt: Date()
    ))
}
```

## 五、关键风险

1. **App Group container 在 ad-hoc 签名下可能创建失败** → 必须先按 `app-group-ad-hoc-signing.md` § 一.4 验证
2. **Darwin Notification 名长度限制 ~255 字符** → 名称用反向域名风格，远不会超
3. **多个请求快速触发时 file name 冲突** → UUID 已经避免
4. **主 App 未启动时 Darwin Notif 无人收**，但请求已落盘，主 App 启动时 `drainPending()` 会扫到 → 闭环成立
5. **`NSWorkspace.shared.open` 在 Extension 中打开 `rightmenu://` URL** 是否会被 sandbox 拒绝？理论上不会（同样是 LaunchServices），但需要实测。如果被拒，降级路径就失效，必须靠 App Group 主路径

## 引用

- Apple Doc: `NSXPCConnection`, `CFNotificationCenter`, `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`
- Apple Doc: `NSWorkspace.OpenConfiguration` — 跨进程打开 URL 的官方方式
- 当前仓库 `FinderExt/FinderSyncActions.swift:19-32` — Extension 内 `NSWorkspace.open` 已验证可用（当前打开 Terminal 就是走这套）
