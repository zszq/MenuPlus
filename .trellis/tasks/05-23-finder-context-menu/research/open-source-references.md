# 开源参考项目

**目的**：列举已知开源 macOS FinderSync 扩展项目，看它们的 App Group / IPC / 错误回报选型。

## 声明

本轮研究**未运行实时 Web/GitHub 搜索**（exa / web_search 工具未在当前会话挂载）。
本文件内容基于研究者训练数据（截至 2026-01）的开源知识，**所有具体细节在引用前必须用 GitHub 实物核对**。

## 一、已知项目

### 1. Nextcloud Desktop Client — macOS FinderSync Extension

- **仓库**：`nextcloud/desktop`
- **路径**：`shell_integration/MacOSX/`
- **架构**：
  - 主 client 进程不开 sandbox
  - Extension 开 sandbox
  - **IPC 选型**：本地 socket（`AF_UNIX`）+ App Group container 下的 socket 文件
  - Extension 通过 socket 给主 client 发请求："给我这个文件的 sync 状态"，主 client 回 badge id
  - 启动顺序：Extension 启动时连接主 client；如果连不上就显示默认 badge

**对本项目的启发**：
- UNIX socket 是另一种可能的 IPC 选项（本项目研究中没列出，因为 sandbox + UNIX socket 配置复杂，且 NSXPCConnection 是更现代的等价物）
- 它们的请求-响应模式可以参考
- App Group container 用作存放 socket 文件而不是 plist

### 2. Dropbox — FinderSync Extension（闭源，但有公开技术博客）

- 旧版用 SIMBL 插件注入 Finder（macOS 10.10 之前），后改用 FinderSync
- **IPC 选型**（推测）：XPC service + 共享 Group container
- Dropbox 有 Apple Developer 账号，所以他们 App Group 走的是标准 `<TeamID>.com.dropbox.xxx`

### 3. Syncthing macOS / SyncTrayzor

- Syncthing 主程序是 Go 服务，FinderSync 是独立 Swift extension
- IPC 选型：HTTP REST 请求到 Syncthing 守护进程的 localhost API（特殊场景：因为主程序本身就是 HTTP 服务）
- 启动管理：守护进程做服务化

**对本项目不适用**：rightMenu 不是 daemon 服务，没有 HTTP API。

### 4. Maccy / Rectangle / Stats（菜单栏 App 参考）

虽然这些不是 FinderSync 项目，但都是**菜单栏 App + LSUIElement**的开源参考，
适合参考 SMAppService + MenuBarExtra 的工程结构。

- **Rectangle**（`rxhanson/Rectangle`）：MenuBarExtra + SMAppService 完整示例
- **Maccy**（`p0deje/Maccy`）：剪贴板菜单栏 App，UNUserNotificationCenter 使用范式
- **Stats**（`exelban/stats`）：复杂菜单栏 App，多模块结构

### 5. Git Trip / git-finder（小型 FinderSync 工具）

GitHub 上有若干小型 FinderSync 项目（搜索关键词 `FIFinderSync` + Swift 通常能找到 20+ 个仓库）：

- 常见模式：
  - 大多数都**不用 App Group**（因为他们也没 Apple Dev 账号）
  - 用 `Process` + AppleScript（在 sandbox 关闭时）
  - 启用 sandbox 的话退化到只支持复制路径、只读操作
- 没找到广泛认可的"sandbox extension + 无 sandbox 主 App + IPC 代办"开源参考

## 二、命名约定参考

观察开源项目的 App Group ID 命名：

| 项目 | App Group ID 模式 |
|---|---|
| Nextcloud | `com.nextcloud.desktopclient` |
| Dropbox（推测） | `<TeamID>.com.dropbox.<feature>` |
| 通用 macOS 习惯 | `group.<reverse-domain>` 或 `<TeamID>.group.<reverse-domain>` |

**对本项目的建议**：
- 用 `group.zl.rightMenu`（短、清晰、与主 bundle id 一致）
- 不用 Team ID 前缀（因为没有 Team ID）

## 三、错误回报模式

开源项目里常见的失败回报模式：

1. **Nextcloud**：错误状态用 badge 颜色反映（同步失败显示红 badge），不弹通知
2. **Maccy**：操作失败用 `UNUserNotificationCenter` 弹通知
3. **Syncthing**：错误写到日志文件，UI 端拉日志展示

本项目推荐路线（`failure-reporting.md` 已详细写）：UNUserNotificationCenter + 菜单栏列表，
与 Maccy 模式一致。

## 四、需要 GitHub 实测核对的事项

在 implement 阶段，建议拉以下仓库做一次实物核对：

```bash
# 核对 Nextcloud Finder Extension 的 IPC
git clone --depth 1 https://github.com/nextcloud/desktop
find desktop/shell_integration/MacOSX -name "*.swift" -o -name "*.entitlements" -o -name "*.plist"

# 找其他 FIFinderSync 项目
# GitHub 搜索: language:Swift FIFinderSync ENABLE_APP_SANDBOX
```

具体要看：
1. 他们的 entitlements 文件长什么样
2. 主程序怎么注册 IPC 监听
3. 怎么处理"主程序未启动"场景

## 五、对本项目的启发汇总

| 借鉴点 | 来源 | 在本项目中怎么用 |
|---|---|---|
| App Group container 作为 IPC 媒介 | Nextcloud | 本项目主推荐方案 |
| UNUserNotificationCenter 主 App 端弹通知 | Maccy | 本项目 failure-reporting 推荐 |
| MenuBarExtra + SMAppService 工程结构 | Rectangle | 本项目已实现 |
| 短 group id 命名 | 通用习惯 | `group.zl.rightMenu` |

## 六、本节的不确定性

由于未跑实时 web search：
- Nextcloud 的具体 IPC 实现细节是研究者记忆中的概念，实际代码可能已经迭代过几版
- "大多数小型 FinderSync 项目不用 App Group" 是统计性印象，没有数字支撑
- Dropbox 部分内容是推测，未引用具体技术博客

**建议在 implement 阶段花 30 分钟做一次 GitHub 搜索 + Nextcloud 仓库实读，校正本文件**。
