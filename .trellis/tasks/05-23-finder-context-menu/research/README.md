# Research Index — FinderSync ↔ Main App IPC

本目录研究 FinderSync extension（强制 sandbox）与主 App（无 sandbox）之间的 IPC 方案，
让"启动外部 App / 写任意路径 / 重启 Finder"这类受限操作由主 App 代办。

## 文件清单

| 文件 | 一句话目的 |
|---|---|
| `app-group-ad-hoc-signing.md` | 回答"ad-hoc 签名能否用 App Group"以及最简配置 / 平替路线 |
| `ipc-options.md` | 五种 IPC 通道（XPC / Darwin Notif / NSDistNotif / App Group UserDefaults / 共享文件）的对比表 + 推荐 + 伪代码骨架 |
| `wakeup-strategy.md` | 主 App 未启动时如何被唤醒（NSWorkspace.openApplication / LaunchAgent / SMAppService / 队列回放） |
| `failure-reporting.md` | 主 App 执行失败时如何异步告知用户（UNUserNotificationCenter / NSAlert / 共享状态文件） |
| `open-source-references.md` | 已知开源 FinderSync 项目 + 它们的 IPC / App Group / 错误回报选型（基于研究者训练知识，需 GitHub 实物核对） |
| `recommendation.md` | **TL;DR**：综合推荐路线 + 工作量估算 + 风险清单 |

## 阅读顺序

1. `recommendation.md` — 直接看结论
2. `app-group-ad-hoc-signing.md` — 决定 App Group 能否走通（这是所有方案的前置）
3. `ipc-options.md` — 选定通道
4. `wakeup-strategy.md` + `failure-reporting.md` — 解决完整闭环
5. `open-source-references.md` — 借鉴他人

## 重要前提

- 当前签名：**ad-hoc / Sign to Run Locally**，无 Apple Developer 账号，无 Team ID
- 主 App bundle id：`zl.rightMenu`（无 sandbox）
- Extension bundle id：`zl.rightMenu.FinderExt`（强制 sandbox + `files.user-selected.read-write`）
- macOS 15.7.3 Sequoia + Xcode 26.3 SDK
- 当前 entitlements 与 sandbox 状态：见 `FinderExt/FinderExt.entitlements` 和 `rightMenu/rightMenu.entitlements`

## 研究方法说明

本轮研究**未启用** Web/MCP 在线搜索（运行环境未挂载 exa/web_search 工具）。
所有结论基于：
1. Apple 官方文档（researcher 训练知识，截至 2026-01）
2. 当前仓库实际配置（`project.pbxproj` / entitlements / Info.plist 实读）
3. macOS 平台公开行为（PluginKit / sandbox / codesign / App Group 一般规则）

**风险**：Apple 的 ad-hoc + App Group 行为在 macOS 15 Sequoia 上可能与训练数据略有出入。
所有"需要 Apple Developer 账号"的判断在实施阶段必须用一次最小可行测试核实
（推荐：先按 `app-group-ad-hoc-signing.md` 的最小测试脚本跑一次）。
