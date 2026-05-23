# 综合推荐 + 工作量估算 + 风险清单

**目的**：TL;DR 形式给出推荐路线、需要改动的文件清单、工作量估算、风险列表。

## 一、TL;DR 推荐路线

### 主路线：**App Group 共享文件队列 + Darwin Notification + NSWorkspace.openApplication 唤醒**

```
[Extension]                                  [Main App]
   │                                              │
   ├── 1. 写 request JSON 到                       │
   │      ~/Library/Group Containers/             │
   │      group.zl.rightMenu/requests/<uuid>.json │
   │                                              │
   ├── 2. Darwin Notify                           │ ──┐
   │      "zl.rightMenu.newRequest"               │   │ 主 App 已在跑：
   │                                              │   │ 立即 drainPending()
   │                                              │   │ → 执行 → 失败时 UNUserNotif
   │                                              │   │
   └── 3. NSWorkspace.openApplication(at:           │ ──┘
          activates: false)                       │
                                                  │ 主 App 未在跑：
                                                  │ LaunchServices 启动它
                                                  │ → applicationDidFinishLaunching
                                                  │ → IPCServer.start()
                                                  │ → drainPending() 处理积压
```

### 降级路线：**URL Scheme + Darwin Notification**（如 App Group 走不通）

完全不依赖 App Group。Extension 用 `NSWorkspace.open(URL("rightmenu://action?path=..."))`，
主 App 用 `.onOpenURL` 接收。URL 长度限制 ~2KB，对当前 6 个动作足够。

### 何时切到降级路线？

按 `app-group-ad-hoc-signing.md` § 一.4 跑一次实测：

```bash
ls ~/Library/Group\ Containers/group.zl.rightMenu
```

返回目录不存在 / 主 App 里 `containerURL(for:)` 返回 nil → 切降级。

## 二、需要新增 / 修改的文件清单

### 新增文件

| 路径 | 内容 | 行数估算 |
|---|---|---|
| `Shared/IPCRequest.swift` | 共享请求/响应 Codable 类型 | ~40 |
| `Shared/IPCConstants.swift` | App Group ID、Darwin Notif 名、URL Scheme 常量 | ~15 |
| `rightMenu/IPC/IPCServer.swift` | 主 App 端 IPC 服务（监听 + drain + 执行分发） | ~120 |
| `rightMenu/IPC/IPCExecutor.swift` | 主 App 端各动作的具体执行实现（openTerminal、createFile、killall 等） | ~150 |
| `rightMenu/IPC/FailureNotifier.swift` | UNUserNotificationCenter 包装 | ~40 |
| `rightMenu/IPC/FailureStore.swift` | UserDefaults 持久化最近失败 | ~30 |
| `FinderExt/IPC/IPCClient.swift` | Extension 端 IPC 客户端（写文件 + Darwin Notif + 唤醒主 App） | ~80 |
| `FinderExt/IPC/AppLauncher.swift` | Extension 端 NSWorkspace.openApplication 包装 | ~30 |

### 修改文件

| 路径 | 改动 | 行数估算 |
|---|---|---|
| `FinderExt/FinderExt.entitlements` | 加 `application-groups` | +5 |
| `rightMenu/rightMenu.entitlements` | 加 `application-groups` | +5 |
| `rightMenu/Info.plist` | 加 `CFBundleURLTypes`（URL scheme 降级用） | +12 |
| `rightMenu/rightMenuApp.swift` | `applicationDidFinishLaunching` 调 `IPCServer.start()` + 请求通知权限 | +10 |
| `rightMenu/MenuBarView.swift` | 加"最近失败"子菜单 | +20 |
| `FinderExt/FinderSyncActions.swift` | 把直接执行改为发 IPC 请求；保留剪贴板/复制路径（无需 IPC） | -30 / +30（重构） |
| `rightMenu.xcodeproj/project.pbxproj` | 加 App Groups capability、加新文件 reference | 工具修改 |

### 行数汇总

- 新增代码：~505 行
- 修改代码：净 +50 行（FinderSyncActions 替换 30 行，加 entitlement 等 ~20 行）
- **总工作量：~550 行 Swift + 配置改动**

## 三、按 Phase 拆分

### Phase 0：可行性验证（30 分钟）

- 给两个 target 加 `application-groups` entitlement
- 启动主 App，跑 `ls ~/Library/Group Containers/`
- 主 App 与 Extension 各打一行 `NSLog` 输出 `containerURL(for:)` 结果
- **结果决定走主路线还是降级路线**

### Phase 1：IPC 骨架（半天 ~ 1 天）

- 写 Shared/IPCRequest、IPCConstants
- 主 App 写 IPCServer + drainPending（先空实现 execute）
- Extension 写 IPCClient（写文件 + Darwin Notif + 唤醒）
- 测试：在 Extension 触发一个动作，主 App console 应能看到 request 落地与读取的日志

### Phase 2：迁移 5 个受限动作

按当前 PRD，需要 IPC 代办的有：
1. 在终端中打开（当前 sandbox 下用 `NSWorkspace.open + Terminal.app` 可能能工作，需要验证；如果失败走 IPC）
2. 在 VSCode 中打开（用 `vscode://` URL，sandbox 下 NSWorkspace.open(URL) 可用，**可能不需要 IPC**）
3. 新建空白文件（当前已限制 `allSelectedAreFolders` + `user-selected.read-write`，**已可用**，可选迁移）
4. 新建 txt 文件（同上）
5. 在新 Finder 窗口中打开（`NSWorkspace.open(URL)` 走 LaunchServices，**应可用**）
6. **切换隐藏文件（Phase 2 想恢复）**：`Process` 调 `killall Finder` 在 sandbox 下被拒，**必须走 IPC**

**重新评估**：当前 sandbox 下用 `NSWorkspace.open` 已经能走通大部分动作（项目最近一次 commit
`d2a9401 feat: add Finder Sync Extension with 8 right-click menu actions` 已经实现并验证）。
**只有"切换隐藏文件 + killall Finder"是明确需要 IPC 的**。

**修订建议**：

| 动作 | 当前状态 | 是否需 IPC | 优先级 |
|---|---|---|---|
| 在终端中打开 | 已用 NSWorkspace.open | 否（实测可用） | - |
| 在 VSCode 中打开 | 已用 NSWorkspace.open(URL) | 否 | - |
| 复制路径/文件名 | 已用 NSPasteboard | 否 | - |
| 新建文件/txt | 已用 user-selected.rw | 否（已 work） | - |
| 在新 Finder 窗口打开 | 已用 NSWorkspace.open | 否 | - |
| **切换隐藏文件** | **未实现** | **是** | **高** |
| **未来用户自定义脚本** | 未实现 | **是** | 中 |

**所以 IPC 的真实驱动力是"未来"**：
- Phase 2 切换隐藏文件
- Phase 3 用户自定义菜单项里可能执行任意命令

**这改变了实施策略**：

- **如果只需要切换隐藏文件 1 个动作 → 用极简降级方案：URL Scheme**，工作量从 550 行降到 ~100 行
- **如果展望 Phase 3 用户自定义命令 → 必须搭完整 IPC**，建议直接搭 App Group 主路线

## 四、最小可行方案（仅为切换隐藏文件）

如果当前 Phase 2 只想加"切换隐藏文件"，**完全可以跳过 App Group**：

### 改动清单（仅 ~100 行）

1. **主 App Info.plist**：加 `CFBundleURLTypes` 注册 `rightmenu://` (+12 行)
2. **主 App rightMenuApp.swift**：`onOpenURL` 解析 → 执行 `defaults write` + `killall Finder` (+30 行)
3. **Extension FinderSyncActions.swift**：加 `static func toggleHiddenFiles()` 调用 `NSWorkspace.open(URL("rightmenu://toggleHidden"))` (+15 行)
4. **Extension FinderSync.swift**：加菜单项 (+5 行)
5. **失败回报**：主 App 在 `defaults` 或 `killall` 失败时弹 UNUserNotification (+30 行)

**这是最小代价获得切换隐藏文件功能的方案**。

## 五、风险清单（汇总）

### 高风险（可能阻塞实施）

1. **App Group container 在 ad-hoc 签名下创建失败**
   - 缓解：先做 Phase 0 可行性验证；失败就走 URL Scheme 降级
2. **`NSWorkspace.openApplication` 在 Extension sandbox 下被拒**
   - 缓解：用 `NSWorkspace.open(URL)` 唤起 URL Scheme 替代
3. **`killall Finder` 在主 App 无 sandbox 下也可能受 Apple Events 权限限制**
   - 主 App entitlement 已有 `apple-events: true`
   - `Process` 执行 `/usr/bin/killall` **不需要** Apple Events 权限（这是 fork+exec 不是 AppleScript）
   - 但用户首次运行可能弹"允许 rightMenu 控制系统？"对话框（非 Apple Events 而是 TCC PPPC 提示）

### 中风险

4. **`defaults write com.apple.finder` 在非 sandbox 主 App 中写入用户域 defaults** — 应该可行，但是 macOS 14+ TCC 加固后可能有提示
5. **主 App 启动时立刻 `requestAuthorization` UNUserNotificationCenter** 在首次启动可能弹很多窗口（onboarding + 通知权限），UX 排序需要设计
6. **多个 Extension 实例并发**（用户同时右键多个 Finder 窗口）：UUID 文件名能避免冲突，但要注意 `drainPending` 用 serial queue 避免重复处理

### 低风险

7. URL 长度 2KB 限制 — 当前动作 payload 都很小
8. Darwin Notif 丢失 — 落盘队列兜底
9. 主 App 崩溃 — 重启时 drainPending 重放

## 六、最终决策树（给 implement 阶段用）

```
问题：当前 Phase 2 是什么范围？

  ├── 只加"切换隐藏文件" 1 个动作
  │     → 走 § 四 最小可行方案（URL Scheme，~100 行）
  │
  └── 展望 Phase 3 用户自定义菜单 + 可能多个 IPC 动作
        → 走 § 一 主推荐路线（App Group + 文件队列，~550 行）
        → 先做 Phase 0 可行性验证决定是否能用 App Group
```

## 七、给 implement 阶段的"开工前 30 分钟"

无论走哪条路线，建议先：

1. ✅ 读完 `app-group-ad-hoc-signing.md`
2. ✅ 加上 App Groups entitlement 并 build 一次
3. ✅ 跑：`ls ~/Library/Group\ Containers/`，看容器是否被创建
4. ✅ 主 App 里 print `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.zl.rightMenu")`
5. ✅ Extension 里同样 print
6. ✅ 两边返回相同非 nil URL → 走主路线；否则降级

把这 6 步的结果记到 `.trellis/tasks/05-23-finder-context-menu/notes/phase0-feasibility.md`，**然后再决定写哪一套实现**。

## 引用

所有具体技术细节见同目录其他研究文件：
- `app-group-ad-hoc-signing.md`
- `ipc-options.md`
- `wakeup-strategy.md`
- `failure-reporting.md`
- `open-source-references.md`
