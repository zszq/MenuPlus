# Phase 0 可行性验证结果

> 执行时间：2026-05-23
> 执行者：trellis-implement sub-agent
> 目标：实测 App Group / URL Scheme 两条 IPC 通路在当前 ad-hoc 签名环境下的可行性。

## 一、关键结论（TL;DR）

**App Group 主路线在当前 ad-hoc 签名环境下完全不可行**。Xcode 在构建阶段就拒绝 `com.apple.security.application-groups` entitlement，报：

```
error: "FinderExt" has entitlements that require signing with a development certificate.
       Enable development signing in the Signing & Capabilities editor.
error: "rightMenu" has entitlements that require signing with a development certificate.
       Enable development signing in the Signing & Capabilities editor.
```

切到 `CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=-` 也失败：

```
error: "rightMenu" requires a provisioning profile.
error: "FinderExt" requires a provisioning profile.
```

这意味着 `app-group-ad-hoc-signing.md` § 一.1 描述的 "macOS 接受裸 `group.zl.rightMenu`、ad-hoc 签名不强制服务端校验" 的乐观推断**在 Xcode 26 + 当前 SDK 下不成立**。**没有 Apple Developer 账号 / 真实 Team ID 就无法启用 application-groups entitlement**。

**因此后续 IPC 必须走 URL Scheme 降级路线**（见 `recommendation.md` § 四 最小可行方案）。

## 二、文件改动清单

### 改动并保留的（URL Scheme 通路骨架）

| 路径 | 改动 |
|---|---|
| `rightMenu/Info.plist` | 新增 `CFBundleURLTypes`，注册 `rightmenu://` scheme |
| `rightMenu/rightMenuApp.swift` | `applicationDidFinishLaunching` 打 App Group container 诊断日志（期望 nil）；新增 `application(_:open:)` 接收并 NSLog 收到的 URL |
| `FinderExt/FinderSync.swift` | `init()` 打 App Group container 诊断日志；`buildSubmenu()` 末尾加临时 `📡 IPC Ping` 菜单项，点击后 `NSWorkspace.shared.open(URL("rightmenu://ping?source=ext"))` |

### 改动后回滚的（App Group entitlement）

| 路径 | 状态 |
|---|---|
| `rightMenu/rightMenu.entitlements` | 曾加 `application-groups = [group.zl.rightMenu]` → 构建失败 → **已移除**，留注释说明结论 |
| `FinderExt/FinderExt.entitlements` | 同上 |

### 没改动

- `rightMenu.xcodeproj/project.pbxproj`（未添加 App Groups capability，因为无 Team ID 也无效）
- `FinderExt/FinderSyncActions.swift`
- `rightMenu/MenuBarView.swift`

## 三、构建结果

```bash
xcodebuild -project rightMenu.xcodeproj -scheme rightMenu clean
# ** CLEAN SUCCEEDED **

xcodebuild -project rightMenu.xcodeproj -scheme rightMenu -configuration Debug build
# ** BUILD SUCCEEDED **
```

- 零 error，零 warning（仅 `xcodebuild: WARNING: Using the first of multiple matching destinations` 这种 destination 警告，与代码无关）
- 签名身份：`Sign to Run Locally`（ad-hoc）

## 四、Sub-agent 环境下可做的辅助诊断

我作为 sub-agent 无法运行主 App / 触发 Finder 右键，但可以验证文件系统层：

```bash
ls -la ~/Library/Group\ Containers/ | grep -iE "rightmenu|zl\."
# 输出：
# drwx------@ 9 zl staff 288 Apr  5 22:49 group.GR99S2ZJZQ.rightmenu-master
```

`GR99S2ZJZQ.rightmenu-master` 是**另一个无关 App**（带 Team ID 的开发者构建）。
**没有 `group.zl.rightMenu` 目录**，与上面 entitlement 被拒的结论一致：系统压根没机会创建该目录。

## 五、给用户的真机验证 checklist

虽然 App Group 已经确定走不通，仍有两件事需要用户实测：

### 验证 A：URL Scheme 通路（关键，决定降级方案是否可行）

1. 打开 `rightMenu.xcodeproj`，点 Xcode 工具栏 **Run**（▶️）按钮启动主 App
   - 应看到菜单栏出现 `filemenu.and.cursorarrow` 图标
   - Xcode console 应打出：
     ```
     [rightMenu/MainApp] App Group container = nil
     ```
     （nil 是预期结果，再次确认 App Group 不可用）

2. 启用 Finder 扩展：系统设置 → 隐私与安全性 → 扩展 → Finder 扩展 → 勾选 `rightMenu`
   - 在 Console.app（不是 Xcode console，因为 Extension 跑在独立进程）搜索 `rightMenu/FinderExt`，应能看到：
     ```
     [rightMenu/FinderExt] App Group container = nil
     ```

3. 打开 Finder，右键任意文件/文件夹，展开 `rightMenu` 子菜单，应看到最底部新增的 `📡 IPC Ping` 菜单项；点击它

4. 观察主 App 的 Xcode console 应打出：
   ```
   [rightMenu/MainApp] 收到 URL: rightmenu://ping?source=ext
   ```

   - **如果看到 → URL Scheme 通路 OK，降级方案可用，进入 Phase 1**
   - **如果只在 Extension 侧看到 `已发送 rightmenu://ping`，但主 App 没收到 URL → 需要查 LaunchServices 注册**：
     ```bash
     /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
       -dump | grep -i rightmenu
     ```
     确认 `rightMenu.app` 已注册为 `rightmenu://` scheme 的 handler；
     必要时先手动跑一次 `open rightmenu://ping?source=manual` 测试主 App 能否被唤起。

### 验证 B：把日志贴回来

请把下面 4 段日志（哪怕是空的）贴给下一轮：

1. **主 App 启动时 Xcode console 的 `[rightMenu/MainApp] App Group container = ...`**
2. **Console.app 里 Extension 的 `[rightMenu/FinderExt] App Group container = ...`**
3. **点 IPC Ping 后 Extension 侧 `[rightMenu/FinderExt] 已发送 rightmenu://ping`**
4. **主 App 端 `[rightMenu/MainApp] 收到 URL: ...`** 是否打印

## 六、下一步建议

根据 URL Scheme 通路验证结果分支：

```
URL Scheme 通路 → 主 App 能收到 URL
  ├── ✅ 收到 → 进入 Phase 1 (URL Scheme + Darwin Notification 降级方案, ~100 行)
  │     1. 删除 IPC Ping 临时菜单项
  │     2. 设计 URL 参数格式：rightmenu://<action>?path=<urlencoded>
  │     3. 主 App 写 URLActionRouter，把收到的 URL 分发到执行器
  │     4. Extension 把"切换隐藏文件"等 sandbox 受限动作改为发 URL
  │
  └── ❌ 收不到 → 退一步排查：
        - 检查 Info.plist 的 CFBundleURLTypes 是否被正确读到（lsregister -dump）
        - 必要时给主 App 加 LSHandlerRank/LSItemContentTypes
        - 极端情况下走 `wakeup-strategy.md` 的兜底方案
```

如果用户后续接入 Apple Developer 账号，可以重新启用 entitlements 文件里被注释掉的 `application-groups` 段，切回主路线。

## 七、未删除的"待清理"项

下列改动是 Phase 0 临时观察用的，待 Phase 1 实施时**统一替换或清理**：

- `FinderExt/FinderSync.swift` 中的 `📡 IPC Ping` 菜单项 + `actionIPCPing` 方法（带 `// Phase 0 验证临时菜单项，验证完会删除` 注释）
- `rightMenu/rightMenuApp.swift` 中 `application(_:open:)` 仅 NSLog 不分发，Phase 1 改成真正的 URLActionRouter
- 三处 `NSLog([rightMenu/...]...)` 诊断日志，Phase 1 可保留为正式日志或迁到统一 Logger
- 两个 entitlements 文件中关于 application-groups 的"已废弃"注释块，确认放弃 App Group 路线后可整体删除
