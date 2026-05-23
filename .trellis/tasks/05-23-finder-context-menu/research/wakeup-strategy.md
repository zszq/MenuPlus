# 主 App 唤醒策略

**目的**：分析 Extension 需要"代办"时，如果主 App 未启动，怎么把主 App 拉起来或让请求排队。

## 一、问题陈述

- FinderSync extension 是 `LSPlugInKitProxy` 进程，**不能**直接 spawn 主 App
- 主 App 是菜单栏 App，用户可能没开
- IPC 落盘（App Group 文件队列）能解决"持久化"，但不能解决"立即处理"

## 二、三条唤醒路径

### 路径 1：`NSWorkspace.shared.openApplication` / `NSWorkspace.shared.launchApplication`

**API**：

```swift
let appURL = ... // 主 App .app bundle URL
NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration()) { app, error in
    // ...
}
```

**问题**：
- Extension 怎么知道主 App 的路径？主 App 在 `/Applications/rightMenu.app` 或用户拖到任意位置都可能
- 可以用 bundle id 反查：`NSWorkspace.shared.urlForApplication(withBundleIdentifier: "zl.rightMenu")`
- **sandbox 下 `NSWorkspace.shared.openApplication(at:)` 是否被允许？** 这是 LaunchServices 调用，
  和 `open(url:)` 同级，理论上允许；但 **`openApplication(at:)`(macOS 11+) 在 sandbox 下确实允许，
  这是 Apple 推荐的现代 API**

**结论**：✅ 可行，**推荐**。

### 路径 2：LaunchAgent 让主 App 常驻

**机制**：在 `~/Library/LaunchAgents/zl.rightMenu.plist` 注册一个 launchd job，让主 App 开机/登录时自动启动并保持运行。

**问题**：
- 已经有 `SMAppService.mainApp.register()`（见 `rightMenu/MenuBarView.swift:48-51`），这就是 macOS 13+ 现代版的 LaunchAgent
- **SMAppService.mainApp 只负责登录时启动一次**，**不负责崩溃后重启**（不像 `KeepAlive=true` 的传统 launchd job）
- 如果用户手动退出主 App（点了菜单栏的"退出 rightMenu"），下次开机前主 App 不会自动起

**改进选项**：
- 用 `SMAppService.daemon(plistName:)` 或 `SMAppService.agent(plistName:)`，配上自定义 plist 设 `KeepAlive=true`
- 或者保持现状（`SMAppService.mainApp`），但接受"用户退出后必须重启主 App"的事实

**结论**：⚠️ 不能依赖 LaunchAgent 保证主 App 一直在跑，只能让"登录时自动起一次"。

### 路径 3：让 Extension 自己唤醒主 App（即"路径 1"的具体调用时机）

**触发时机**：
- 在 `FinderSyncActions` 里写入请求文件后，**立即调用 `openApplication`**
- 主 App 已在跑 → LaunchServices 会激活已有实例，不会启动第二份
- 主 App 没在跑 → LaunchServices 启动它，`applicationDidFinishLaunching` 中 `IPCServer.start()` 会 `drainPending()` 处理积压

## 三、推荐策略（组合）

### 策略：被动唤醒 + 队列回放

```
Extension 触发动作时：
  1. 写请求文件到 App Group container 的 requests/<uuid>.json
  2. 发 Darwin Notif（如果主 App 在跑，立即处理）
  3. 调 NSWorkspace.shared.openApplication(at: 主App URL)（如果没在跑，启动并 drain）
```

```swift
// Extension 端
enum AppLauncher {
    static func ensureMainAppRunning() {
        guard let url = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: "zl.rightMenu")
        else {
            NSLog("[rightMenu] 找不到主 App")
            return
        }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = false  // 不抢焦点，菜单栏 App 默认隐式后台
        cfg.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, error in
            if let error = error {
                NSLog("[rightMenu] 启动主 App 失败: \(error)")
            }
        }
    }
}
```

### 关于焦点：`activates = false`

`NSWorkspace.OpenConfiguration.activates = false`（macOS 11+）告诉 LaunchServices**不要把主 App 切到前台**，
这正好符合菜单栏 App 的 UX 要求 — 用户右键 → 菜单栏 App 在后台被唤起 → 处理 → 用户无感。

### 主 App 启动顺序

```
applicationDidFinishLaunching
  ├── IPCServer.start()
  │     ├── 注册 Darwin Notif observer
  │     └── drainPending()  // 处理 Extension 积压的请求
  ├── 现有 onboarding 引导（仅首次）
  └── 菜单栏图标已由 SwiftUI MenuBarExtra 自动注册
```

## 四、用户必须先做的事

按推荐策略，用户**不需要**先手动启动主 App。但有几个隐性要求：

1. **主 App 必须装在 LaunchServices 可识别的位置**（`/Applications/` 或用户拖过的地方）
   - Xcode debug 直接 run 出来的 .app 也会被 LaunchServices 索引，但路径可能频繁变化
   - 真机分发场景：建议引导用户拖到 `/Applications/`，或用 SMAppService 间接注册
2. **首次安装后**，用户必须至少打开过一次主 App，让 LaunchServices 注册 bundle id
3. 用户在系统设置里启用了 Finder 扩展（这是 PRD 已有的引导）

## 五、降级方案

如果 `NSWorkspace.shared.openApplication` 在 Extension sandbox 下被拒（不太可能但要兜底）：

- 用 URL Scheme：`NSWorkspace.shared.open(URL(string: "rightmenu://wake")!)` 来变相启动主 App
  - 主 App 的 `onOpenURL` 收到后视作 "wake-up ping"，触发 `IPCServer.drainPending()`
  - 这种方式利用 `rightmenu://` scheme 注册到主 App，URL open 必然启动主 App

## 六、风险清单

| 风险 | 影响 | 缓解 |
|---|---|---|
| `openApplication` 在 sandbox 下被拒 | 主 App 不被唤起，请求积压到下次启动 | 降级到 URL Scheme |
| 用户卸载主 App 但 Extension 还在 | bundle id 查找返回 nil | 写 NSLog，请求文件留在 group container 当作"无人认领" |
| 主 App 启动慢，drain 之前用户已经看不到效果 | 用户感觉"卡了一下" | drain 在主 App 后台队列异步执行，UI 不阻塞 |
| 多个 Extension 实例并发请求 | 多份 `openApplication` 调用 | LaunchServices 自动去重，只启动一份 |
| 主 App 启动后立刻被退出（用户手动） | 处理中的请求被中断 | 重试机制：执行完成才删请求文件，未删的下次启动重新处理（注意防止"已开终端但重复开"的副作用 → 加 "已处理但未确认" 状态） |

## 引用

- Apple Doc: `NSWorkspace.openApplication(at:configuration:completionHandler:)` (macOS 11+)
- Apple Doc: `SMAppService.mainApp` (macOS 13+)
- 当前仓库 `rightMenu/MenuBarView.swift:48-51` — 已用 SMAppService.mainApp
- 当前仓库 `rightMenu/rightMenuApp.swift:24-32` — applicationDidFinishLaunching 是 IPCServer 的接入点
