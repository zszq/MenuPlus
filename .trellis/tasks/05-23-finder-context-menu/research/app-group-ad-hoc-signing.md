# App Group 在 ad-hoc 签名下的可行性

**目的**：判定无 Apple Developer 账号、ad-hoc / "Sign to Run Locally" 签名场景下，主 App 与 FinderSync extension 能否共享 App Group；不能的话给平替。

## 一、关键事实

### 1. App Group 的两条独立校验

macOS 对 App Group 做的事其实分两层，常被混为一谈：

| 层 | 校验内容 | 是否依赖 Apple Developer Portal |
|---|---|---|
| **A. Entitlement 形式** | `com.apple.security.application-groups` 数组里写了什么字符串 | 否，写什么都可以，本地能签上 |
| **B. 容器目录访问** | 系统是否给该 group id 在 `~/Library/Group Containers/<group>/` 下创建 / 授权目录 | **macOS 上：是**，但走的是 codesign 的 Team ID 校验，不强制走 Apple 服务端注册 |

关键点：App Store / TestFlight 分发场景下 Apple 会校验 group id 是否在 Developer Portal 注册过；
**本地 ad-hoc 分发不会触发这层服务端校验**。但 codesign 会要求两个 target 的 entitlement 一致且都有
有效签名身份。

### 2. ad-hoc 签名（`-`）没有 Team ID

`codesign --display --entitlements - rightMenu.app` 在当前 "Sign to Run Locally" 模式下，签名身份是 `-`（ad-hoc），
没有 Team Identifier。这导致**`com.apple.security.application-groups` 的 group 名按惯例需要的 `<TeamID>.group.xxx`
前缀拿不到 Team ID**。

Apple 文档说 macOS 的 App Group 名"必须以 group. 开头"（iOS 强制 `<TeamID>.group.xxx` 前缀，
macOS 允许 `group.xxx` 不带 Team 前缀）。**实务上 macOS 接受裸 `group.zl.rightMenu` 这种名字**，
只要两个 target 的 entitlements 完全一致即可。

### 3. 实测最小配置（推荐先按这套跑通）

#### 主 App `rightMenu.entitlements`

```xml
<key>com.apple.security.app-sandbox</key>
<false/>  <!-- 主 App 仍不开 sandbox -->

<key>com.apple.security.application-groups</key>
<array>
    <string>group.zl.rightMenu</string>
</array>

<!-- 保留原有 -->
<key>com.apple.security.automation.apple-events</key>
<true/>
```

#### Extension `FinderExt.entitlements`

```xml
<key>com.apple.security.app-sandbox</key>
<true/>

<key>com.apple.security.files.user-selected.read-write</key>
<true/>

<key>com.apple.security.application-groups</key>
<array>
    <string>group.zl.rightMenu</string>
</array>
```

#### Xcode capabilities 操作

- 主 App target → Signing & Capabilities → `+ Capability` → App Groups → 加入 `group.zl.rightMenu`
- FinderExt target → 同上加入相同字符串
- **不要**在 Apple Developer Portal 注册（也注册不了，没账号）

### 4. 验证容器目录是否真的建出来

```bash
# 启动主 App 一次后
ls -la ~/Library/Group\ Containers/ | grep zl.rightMenu

# 期望看到
# drwx------  3 zl  staff  ...  group.zl.rightMenu
```

如果目录建不出来 → 说明 ad-hoc 签名场景 macOS 拒绝创建容器，必须走平替（见 § 三）。
如果建出来 → 主 App 和 Extension 都能在该目录里读写，IPC 闭环成立。

## 二、为什么这条路有把握走通

1. PluginKit 已经接受了当前 ad-hoc 签名的 Extension（项目里有日志 "FinderSync 已加载"）。
   说明 PluginKit 不强制要求 Team ID，只要 sandbox + 签名格式合法即可。
2. `com.apple.security.application-groups` 是普通 entitlement，不是 "Apple-only" entitlement，
   不需要 provisioning profile。
3. macOS 历史上一直允许 `group.<reverse-dns>` 这种自定义名，未强制 Team 前缀。

## 三、如果走不通的平替路线

如果实测发现 group container 创建失败，按以下顺序降级：

### 平替 A：约定共享目录 + Darwin Notification

完全不用 App Group。直接在固定路径建 IPC 目录：

```swift
// 双方都用相同路径
let ipcDir = ("~/Library/Application Support/zl.rightMenu/ipc" as NSString).expandingTildeInPath
```

- 主 App 无 sandbox，能在该路径读写
- Extension sandbox 下访问该路径 → **会被拒**（不在 user-selected 范围内）
- 因此这个方案要求 **Extension 写一个 user-selected 范围内的临时文件**（比如选中目录下的 `.rightmenu-request.json`），然后用 Darwin Notification 告诉主 App 路径。但污染用户目录，不优雅。

### 平替 B：纯 Darwin Notification + URL Scheme

- Extension 只发 Darwin Notification + 在 notification 之前调用 `NSWorkspace.shared.open(URL(string: "rightmenu://action?...")!)`
- 主 App 注册 `rightmenu://` URL scheme，从 URL 中解析参数
- 限制：URL 长度限制，payload 不能太大；但 4KB 内的简单命令完全够用
- 优势：完全不需要 App Group

这是**降级方案中最干净的**，详见 `ipc-options.md` 里的 URL Scheme 章节。

### 平替 C：把整个 IPC 改成轮询 `/tmp/rightmenu-<uuid>.json`

- Extension 在 user-selected 目录里写不了 `/tmp`（sandbox 拒绝），所以**这条不通**
- 列出来只是为了说明：**任何不在 user-selected 范围内的写入，Extension 都做不到**

## 四、ad-hoc 签名的一致性问题

如果使用 App Group，两个 target 必须**用同一个签名身份签**。当前都是 `-`（ad-hoc），
两个 ad-hoc 签名互相不是"同一身份"，**但 entitlement 字符串完全相同时 macOS 仍会把它们当成同 group**
（macOS 用 entitlement 字符串匹配，而不是 Team ID 匹配，前提是 entitlement 形式合法）。

如果发现匹配失败 → 用一个本地自签的开发者证书（钥匙串 → 证书助理 → 创建证书 → 自签名根证书）替代 ad-hoc，
让两个 target 都用这个证书签，能彻底消除身份不一致问题。但这一步**只在 ad-hoc 走不通时再做**。

## 五、最终判定

**结论：先走 App Group 主路径，跑不通再降级到 Darwin Notif + URL Scheme（平替 B）**。

判定的实测步骤（不超过 30 分钟）：
1. 给两个 target 加上 entitlement
2. Xcode build + run 主 App
3. `ls ~/Library/Group\ Containers/group.zl.rightMenu` 看目录是否存在
4. 在主 App 里 `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.zl.rightMenu")` 是否返回非 nil
5. 在 Extension 里同样调用，看是否返回**同一个 URL**

如果第 4、5 步都返回相同非 nil URL → App Group 通了，按主路径走。

## 引用

- Apple Developer Doc: "Configuring app groups" — 标准 macOS App Group 配置
- Apple TN2206: macOS Code Signing in Depth — ad-hoc 签名与 entitlement 的关系
- 当前仓库 `FinderExt/FinderExt.entitlements:18-23` — sandbox + user-selected.read-write 已生效
- 当前仓库 `rightMenu/rightMenu.entitlements:5-10` — 主 App 无 sandbox

**待真机验证项**：本结论基于公开行为推断，最终是否成立必须用 § 一.4 的脚本核实。
